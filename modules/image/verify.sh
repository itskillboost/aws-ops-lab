#!/bin/bash
# image 모듈 정상 상태 판정 공통 — baseline/verify.sh 와 faults/*/verify.sh 가 source 한다.
#   verify_main "<제목>"  → PASS/FAIL 을 출력하고 종료 코드(0=정상)로 끝낸다
# 노드·앱·파드·Argo CD 앱에 더해 파이프라인을 본다: 마지막 실행 성공, 운영 앱이 "내 ECR 의 이미지 = Git 에 적힌 릴리스"를 쓰는지,
# 그 이미지가 스캔 게이트 기준을 지키는지, 가장 최근 앱 커밋이 그 이미지에 들어가 있는지(새 버전이 운영까지 왔는지).
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../common/eks.sh"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/functions.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
NS=$APP_NS; DEP=opslab-app
summary() { echo "== 결과: PASS $PASS / FAIL $FAIL =="; [ "$FAIL" -eq 0 ] && { echo "판정: 정상"; exit 0; } || { echo "판정: 비정상"; exit 1; }; }

verify_main() {
  kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다(kubeconfig)."; exit 2; }
  echo "== $(TZ=Asia/Seoul date '+%F %T') 정상 상태 판정: $SID / $1 =="
  GH_T=$(gh_token); export GH_T

  echo "[1] 노드"
  local nn nr
  nn=$(kubectl get nodes --no-headers | wc -l); nr=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
  [ "$nn" -ge 2 ] && [ "$nr" -eq "$nn" ] && ok "노드 $nr/$nn Ready" || ng "노드 Ready $nr/$nn (기준: 2대 이상 전부 Ready)"

  echo "[2] 운영 앱 Deployment ($NS/$DEP)"
  local j want upd rdy av tot bad
  j=$(kubectl -n "$NS" get deploy "$DEP" -o json 2>/dev/null) || { ng "Deployment 가 없습니다"; j=""; }
  if [ -n "$j" ]; then
    read -r want upd rdy av tot <<<"$(jq -r '[.spec.replicas, .status.updatedReplicas//0, .status.readyReplicas//0, .status.availableReplicas//0, .status.replicas//0]|@tsv' <<<"$j")"
    [ "$upd" -eq "$want" ] && [ "$rdy" -eq "$want" ] && [ "$av" -eq "$want" ] && [ "$tot" -eq "$want" ] \
      && ok "배포 완료: 희망 $want = 최신 $upd = Ready $rdy (진행 중인 새 파드 없음)" \
      || ng "배포 미완료: 희망 $want / 최신 $upd / Ready $rdy / 전체 $tot (kubectl -n $NS rollout status deploy $DEP)"
  fi
  bad=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=opslab-app -o json 2>/dev/null | jq -r '.items[] | select(.metadata.deletionTimestamp==null)
        | select((.metadata.ownerReferences[0].kind // "")!="Job")
        | select(.status.phase!="Running" or ([.status.containerStatuses[]?|.ready]|all|not))
        | "\(.metadata.name) \([.status.initContainerStatuses[]?,.status.containerStatuses[]? | .state.waiting.reason // empty] | join(","))"')
  [ -z "$bad" ] && ok "앱 파드 모두 Running·Ready" || { ng "Running·Ready 가 아닌 앱 파드:"; sed 's/^/         /' <<<"$bad"; }

  echo "[3] Argo CD 앱 (루트·운영·개발)"
  local a l
  for a in $APPS; do l=$(app_line "$a"); [[ "$l" == "Synced Healthy "* ]] && ok "$a Synced·Healthy" || ng "$a: $l (동기화 건강 리비전 작업)"; done

  echo "[4] 파이프라인 ($PIPE)"
  local e s
  if pipe_exists; then
    read -r e s <<<"$(pipe_last)"
    [ "$s" = Succeeded ] && ok "마지막 실행 성공 (${e:0:8})" \
      || { ng "마지막 실행 ${s:-없음} (${e:0:8}) — 실패한 단계:"; pipe_failed "$e" | cut -c1-220 | sed 's/^/         /'; }
  else ng "파이프라인이 없습니다 (1단계 구축 5)"; fi

  echo "[5] 운영 앱 이미지 = 내 ECR 의 릴리스"
  local run grepo gtag rtag cnt crit src
  run=$(running_image); grepo=$(git_release Repository); gtag=$(git_release Tag); rtag=${run##*:}
  [ "${run%:*}" = "$ECR_URI" ] && ok "이미지 저장소: 내 ECR ($REPO_NAME)" || ng "운영 앱이 내 ECR 이 아닌 이미지를 씁니다: $run"
  [ -n "$gtag" ] && [ "$run" = "$grepo:$gtag" ] && ok "Git 에 적힌 릴리스와 같음 ($gtag)" || ng "Git 릴리스($grepo:$gtag)와 운영 앱($run)이 다릅니다"
  if aws ecr describe-images --repository-name "$REPO_NAME" --image-ids imageTag="$rtag" >/dev/null 2>&1; then
    ok "ECR 에 태그 $rtag 가 있음"
    cnt=$(scan_counts "$rtag"); crit=$(jq -r '.CRITICAL // 0' <<<"${cnt:-{\}}" 2>/dev/null)
    [ -n "$cnt" ] && [ "${crit:-1}" -eq 0 ] && ok "스캔 결과 CRITICAL 0개" || ng "스캔 결과가 없거나 CRITICAL 이 있습니다: ${cnt:-없음}"
  else ng "ECR 에 운영 앱이 쓰는 태그 $rtag 가 없습니다(지워졌거나 다른 저장소)"; fi
  src=$(latest_src)
  [ -n "$src" ] && contains "$src" "$rtag" && ok "가장 최근 앱 커밋 ${src:0:7} 이 운영 이미지에 들어 있음" \
    || ng "가장 최근 앱 커밋 ${src:0:7} 이 아직 운영에 반영되지 않았습니다(운영 이미지 태그 $rtag)"

  echo "[6] 사용자 경로 (ALB 로 직접 요청 — /health 3회, /api 10회, 응답의 build = 운영 이미지 태그)"
  local alb c bad2="" b
  alb=$(kubectl -n "$NS" get ingress "$DEP" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$alb" ]; then
    for i in 1 2 3; do c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$alb/health"); [ "$c" = 200 ] || { bad2="$bad2 /health=$c"; break; }; done
    for i in $(seq 1 10); do c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$alb/api"); [ "$c" = 200 ] || { bad2="$bad2 /api=$c"; break; }; done
    [ -z "$bad2" ] && ok "모든 경로 200 응답" || ng "200 이 아닌 경로:$bad2"
    b=$(curl -s -m 8 "http://$alb/api" | jq -r '.build // "없음"' 2>/dev/null)
    [ "$b" = "$rtag" ] && ok "응답의 build=$b (운영 이미지와 같음)" || ng "응답의 build=$b ≠ 운영 이미지 태그 $rtag"
  else ng "Ingress 에 ALB 주소가 없습니다"; fi

  echo "[7] 부하 파드 최근 1분 (ALB 로 초당 10건)"
  local lp lines e5 ce req
  lp=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=opslab-load --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
  lines=$([ -n "$lp" ] && kubectl -n "$NS" logs "$lp" --since=70s 2>/dev/null | grep 'req=' | tail -6)
  if [ -z "$lines" ]; then ng "요청 수 0건 — 부하 파드가 없습니다: bash ~/opslab/common/load.sh pod alb"
  else
    req=$(grep -o 'req=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    e5=$(grep -o '5xx=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    ce=$(grep -o 'conn_err=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    [ "$e5" -eq 0 ] && [ "$ce" -eq 0 ] && ok "요청 $req건 중 5xx 0건·연결 오류 0건" || ng "요청 $req건 중 5xx $e5건·연결 오류 $ce건 (기준 0건)"
  fi
  summary
}
