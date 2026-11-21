#!/bin/bash
# 구축 확인 지점 — 따라하기의 큰 단계마다 실행해 ✅/❌ 로 스스로 확인한다. ❌ 면 무엇이 빠졌는지와 다시 할 단계를 알려 준다.
#   bash ~/opslab/common/check.sh day0               Day 0 자가 점검(도구·L0·권한 경계·GitHub 토큰)
#   bash ~/opslab/common/check.sh workload <단계>    모듈 구축 확인 (단계 이름은 따라하기에 적혀 있다)
#   bash ~/opslab/common/check.sh workload all       모듈의 모든 확인 지점
#   bash ~/opslab/common/check.sh final              과정 마무리(포트폴리오 내려받기 안내)
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
source "$ROOT/common/eks.sh"
N_OK=0; N_NG=0
ok() { echo "  ✅ $1"; N_OK=$((N_OK+1)); }
ng() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     ↳ 다시 할 단계: $2"; N_NG=$((N_NG+1)); }
end() { echo "== ✅ $N_OK / ❌ $N_NG"; [ "$N_NG" -eq 0 ]; exit $?; }

case "${1:-}" in
day0)
  echo "== Day 0 자가 점검 ($SID)"
  [ "$(aws configure get region 2>/dev/null || echo "$AWS_REGION")" = ap-northeast-2 ] && ok "리전 서울(ap-northeast-2)" || ng "리전이 서울이 아닙니다" "CloudShell 오른쪽 위 리전을 서울로"
  for t in kubectl helm eksctl argocd; do command -v $t >/dev/null && ok "도구 $t" || ng "도구 $t 없음" "bash ~/opslab/common/tools.sh"; done
  python3 -c 'import yaml' 2>/dev/null && ok "pyyaml(review.sh 용)" || ng "pyyaml 없음" "bash ~/opslab/common/tools.sh"
  grep -q "^export COURSE=" ~/opslab-env.sh 2>/dev/null && [ -f "$COURSE_FILE" ] && ok "과정 파일: ${COURSE:-}" || ng "~/opslab-env.sh 에 export COURSE=skons-eks 가 없습니다" "Day 0 따라하기 3단계"
  aws cloudformation describe-stacks --stack-name "$SID-l0" >/dev/null 2>&1 && ok "L0 스택 $SID-l0" || ng "L0 스택 없음" "Day 0 따라하기 4단계(L0 배포)"
  U=$(aws sts get-caller-identity --query Arn --output text | cut -d/ -f2)
  aws iam get-user --user-name "$U" --query 'User.PermissionsBoundary.PermissionsBoundaryArn' --output text 2>/dev/null | grep -q opslab-student-boundary \
    && ok "내 IAM 사용자에 권한 경계" || ng "권한 경계가 붙어 있지 않습니다" "Day 0 따라하기 4단계 마지막(NextStep 명령)"
  aws secretsmanager describe-secret --secret-id opslab/github-token >/dev/null 2>&1 && ok "GitHub 토큰 시크릿(opslab/github-token)" || ng "GitHub 토큰 시크릿 없음 (gitops 모듈부터 필요)" "Day 0 따라하기 5단계"
  if [ -n "${GITHUB_REPO:-}" ]; then
    source "$ROOT/common/gh.sh"
    gh_api GET "/repos/$GITHUB_REPO" 2>/dev/null | jq -e '.fork == true and .permissions.push == true' >/dev/null \
      && ok "내 Fork $GITHUB_REPO (토큰으로 쓰기 가능)" || ng "Fork $GITHUB_REPO 를 토큰으로 쓸 수 없습니다(이름·토큰 권한 Contents: Read and write 확인)" "Day 0 따라하기 5단계"
  else ng "~/opslab-env.sh 에 export GITHUB_REPO=<내 GitHub ID>/aws-ops-lab 가 없습니다" "Day 0 따라하기 5단계"; fi
  [ -d ~/opslab/.git ] && ok "실습 저장소 ~/opslab" || ng "실습 저장소 없음" "git clone https://github.com/worldvit/aws-ops-lab ~/opslab"
  end ;;
final)
  echo "== 과정 마무리"
  [ -f ~/opslab-work/portfolio.md ] && ok "포트폴리오 ~/opslab-work/portfolio.md" || ng "포트폴리오가 없습니다" "bash ~/opslab/common/review.sh final"
  echo "  📥 내 PC 로 내려받기: CloudShell [작업] → [파일 다운로드] → /home/cloudshell-user/opslab-work/portfolio.md"
  echo "     계정은 과정 뒤 반납됩니다. 내려받았는지 꼭 확인하세요."
  end ;;
esac

MOD=${1:?모듈 ID}; ST=${2:-all}; F="$ROOT/modules/$MOD/check.sh"
[ -f "$F" ] || { echo "❌ 모듈 확인 지점이 없습니다: modules/$MOD/check.sh"; exit 1; }
have_cluster && kube_login
source "$F"           # STAGES="..." 와 stage_<이름> 함수
if [ "$ST" = all ]; then for s in $STAGES; do echo "== $MOD · $s"; "stage_$s"; done
else
  [[ " $STAGES " == *" $ST "* ]] || { echo "❌ 단계 이름: $STAGES"; exit 1; }
  echo "== $MOD · $ST"; "stage_$ST"
fi
end
