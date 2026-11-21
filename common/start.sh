#!/bin/bash
# 모듈 시작 — 모듈에 필요한 환경 층을 아래부터 차례로 배포한다. CloudShell에서 실행.
#   bash ~/opslab/common/start.sh cmp            # 모듈 시작: requires 층까지 (cmp → L1)
#   bash ~/opslab/common/start.sh cmp full       # 따라잡기: builds 층까지 (cmp → L1, L2 = cmp 완료 상태)
#   bash ~/opslab/common/start.sh workload       # EKS: workload → L1, K1 (클러스터 층은 20분 안팎 걸린다)
#   bash ~/opslab/common/start.sh status         # 층별 진행 상황(완료·진행 중·없음)
# 실패하거나 CloudShell 연결이 끊긴 뒤 같은 명령을 다시 실행하면, 끝난 층은 건너뛰고 끝나지 않은 층부터 이어서 배포한다.
# (CloudFormation 스택은 CloudShell 연결이 끊겨도 계속 만들어진다.)
# 모듈에 env.yaml(주변 구성)이 있으면 층 다음에 <학번>-<모듈>-env 로, full 이고 done.yaml(완료 상태)이 있으면 <학번>-<모듈>-done 으로 배포한다.
# L0 층(<학번>-l0)은 Day 0에 한 번만 배포하며 이 스크립트는 건드리지 않는다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
source "$ROOT/common/eks.sh"
MARK=~/.opslab/start; mkdir -p "$MARK"
TODAY=$(TZ=Asia/Seoul date +%F)

# 층 정의: 파일 이름(템플릿 .yaml 과/또는 설치 스크립트 .sh)과 Module 태그
declare -A FILE=([L1]=l1-network [L2]=l2-app [L3]=l3-data [L4]=l4-secret \
                 [K1]=k1-cluster [K2]=k2-workload [K3]=k3-ingress [K4]=k4-access [K5]=k5-gitops)
declare -A OWNER=([L1]=base [L2]=cmp [L3]=data [L4]=sec [K1]=cluster [K2]=workload [K3]=podnet [K4]=access [K5]=gitops)
chain() {  # $1=맨 위 층(L3, K2 …) → 아래부터 배포할 층 목록
  case "$1" in
    L*) seq -f 'L%g' 1 "${1#L}" ;;
    K*) echo L1; seq -f 'K%g' 1 "${1#K}" ;;
  esac
}
done_mark() { echo "$MARK/$SID-$1"; }
is_done() {  # 오늘 끝낸 층이고, 스택이 있는 층이면 스택도 살아 있어야 완료로 본다
  local f; f=$(done_mark "$1"); [ "$(cat "$f" 2>/dev/null)" = "$TODAY" ] || return 1
  [ -f "$ROOT/layers/${FILE[$1]}.yaml" ] || return 0
  aws cloudformation describe-stacks --stack-name "$SID-${1,,}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null | grep -qE '^(CREATE|UPDATE)_COMPLETE$'
}

if [ "${1:-}" = status ]; then
  echo "== $SID 환경 층 진행 상황 ($TODAY)"
  for l in L1 L2 L3 L4 K1 K2 K3 K4 K5; do
    st=$(aws cloudformation describe-stacks --stack-name "$SID-${l,,}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "-")
    if is_done "$l"; then s="✅ 완료"; elif [ "$st" != "-" ]; then s="⏳ $st"; else continue; fi
    printf '  %-3s %-12s %s\n' "$l" "${FILE[$l]}" "$s"
  done
  exit 0
fi

MOD=${1:?모듈 ID를 적으세요. 예) start.sh workload}; MY="$ROOT/modules/$MOD/module.yaml"
[ -f "$MY" ] || { echo "❌ 모듈이 없습니다: $MOD"; exit 1; }
KEY=requires; [ "${2:-}" = full ] && KEY=builds
TOP=$(sed -n 's/^requires: *\([LK][0-9]\).*/\1/p' "$MY")
B=$(sed -n 's/^builds: *\([LK][0-9]\).*/\1/p' "$MY")
[ "$KEY" = builds ] && [ -n "$B" ] && TOP=$B          # builds 가 층이 아니면(—) requires 까지

aws cloudformation describe-stacks --stack-name "$SID-l0" >/dev/null 2>&1 \
  || { echo "❌ L0 층($SID-l0)이 없습니다. Day 0 준비를 먼저 끝내세요."; exit 1; }

# GitOps 를 쓰는 날(module.yaml 에 fork: true — gitops·image·heal): 내 Fork 를 원본과 동기화하고 오늘 브랜치를 만든다(Argo CD 는 이 브랜치만 본다)
if grep -q '^fork: *true' "$MY"; then
  bash "$ROOT/common/fork.sh" prepare "$MOD" || exit 1
  source ~/opslab-env.sh
fi

params() {  # 층별 추가 매개변수
  case "$1" in
    K1) local ver arn
        ver=$(cval eks_version); grep -q '^eks: *prev' "$MY" && ver=$(cval eks_version_prev)
        arn=$(aws sts get-caller-identity --query Arn --output text)
        # 역할을 맡은 세션(assumed-role)이면 역할 ARN 으로 바꾼다(접근 항목은 역할 단위)
        arn=$(sed -E 's#arn:aws:sts::([0-9]+):assumed-role/([^/]+)/.*#arn:aws:iam::\1:role/\2#' <<<"$arn")
        echo "EksVersion=$ver NodeInstanceType=$(cval node_instance_type) NodeCount=$(cval node_count) StudentPrincipalArn=$arn" ;;
  esac
}
deploy() {  # $1=스택 이름 $2=템플릿 $3=Module 태그 $4=추가 매개변수 — 배포 후 출력값을 환경 파일에 추가(예: ClusterName → CLUSTER_NAME)
  echo "== 배포: $1 ($(basename "$2")) — 수 분 걸립니다 (연결이 끊겨도 스택은 계속 만들어집니다)"
  # shellcheck disable=SC2086
  aws cloudformation deploy --stack-name "$1" --template-file "$2" --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides StudentId="$SID" ${4:-} --tags Course=opslab Module="$3" Owner="$SID" --no-fail-on-empty-changeset \
    | tail -1
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "❌ $1 배포 실패 — 콘솔 CloudFormation 이벤트를 확인하고, 원인을 고친 뒤 같은 명령을 다시 실행하세요."; exit 1; }
  aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output text \
    | while read -r k v; do
        var=$(sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' <<<"$k" | tr a-z A-Z)
        grep -q "^export $var=$v\$" ~/opslab-env.sh 2>/dev/null || echo "export $var=$v" >> ~/opslab-env.sh
      done
}
for l in $(chain "$TOP"); do
  if is_done "$l"; then echo "== $l (${FILE[$l]}) 은 오늘 이미 끝났습니다 — 건너뜀"; continue; fi
  tpl="$ROOT/layers/${FILE[$l]}.yaml"; init="$ROOT/layers/${FILE[$l]}.init.sh"; sh="$ROOT/layers/${FILE[$l]}.sh"
  [ -f "$tpl" ] || [ -f "$sh" ] || { echo "❌ 층이 아직 없습니다: layers/${FILE[$l]}"; exit 1; }
  [ -f "$tpl" ] && deploy "$SID-${l,,}" "$tpl" "${OWNER[$l]}" "$(params "$l")"
  [ -f "$init" ] && { source ~/opslab-env.sh; bash "$init" || { echo "❌ $l 초기화 실패 — 같은 명령을 다시 실행하면 이어서 합니다."; exit 1; }; }   # 층 초기화(예: DB 계정, kubeconfig·Headlamp)
  [ -f "$sh" ] && { echo "== 설치: $l (${FILE[$l]}.sh)"; source ~/opslab-env.sh; bash "$sh" || { echo "❌ $l 설치 실패 — 같은 명령을 다시 실행하면 이어서 합니다."; exit 1; }; }   # 쿠버네티스 리소스만 있는 층
  echo "$TODAY" > "$(done_mark "$l")"
done
# 모듈 주변 구성(env.yaml)과, 따라잡기일 때 모듈 완료 상태(done.yaml)
[ -f "$ROOT/modules/$MOD/env.yaml" ] && deploy "$SID-$MOD-env" "$ROOT/modules/$MOD/env.yaml" "$MOD"
[ "$KEY" = builds ] && [ -f "$ROOT/modules/$MOD/done.yaml" ] && deploy "$SID-$MOD-done" "$ROOT/modules/$MOD/done.yaml" "$MOD"
# 따라잡기: 완료 상태를 템플릿 하나로 만들 수 없는 모듈은 full.sh(따라하기 명령 모음)를 실행한다
[ "$KEY" = builds ] && [ -f "$ROOT/modules/$MOD/full.sh" ] && { source ~/opslab-env.sh; bash "$ROOT/modules/$MOD/full.sh" || exit 1; }

# 오늘의 작업 폴더와 빈 양식(가설·런북) — review.sh 가 이 파일들을 검토한다
W=~/opslab-work/$MOD; mkdir -p "$W"
grep -E '^ *- *[a-z]+-[0-9]+ *\|' "$MY" | sed -E 's/^ *- *([a-z]+-[0-9]+).*/\1/' | while read -r lab; do
  [ -f "$ROOT/runbook/HYPOTHESIS.md" ] && [ ! -f "$W/hypothesis-$lab.md" ] && sed "s/<Lab ID>/$lab/g" "$ROOT/runbook/HYPOTHESIS.md" > "$W/hypothesis-$lab.md"
  [ ! -f "$W/runbook-$lab.md" ] && sed "s/<Lab ID>/$lab/g" "$ROOT/runbook/TEMPLATE.md" > "$W/runbook-$lab.md"
done
echo "✅ $MOD 시작 준비 완료. 'source ~/opslab-env.sh' 로 변수를 불러오세요. 작업 폴더: ~/opslab-work/$MOD/"
