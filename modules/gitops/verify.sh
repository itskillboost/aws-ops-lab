#!/bin/bash
# gitops 모듈 정상 상태 판정 공통 — baseline/verify.sh 와 faults/*/verify.sh 가 source 한다.
#   verify_main "<제목>"  → PASS/FAIL 을 출력하고 종료 코드(0=정상)로 끝낸다
# 노드·앱·파드에 더해, Argo CD 구성 요소, 세 앱(루트·운영·개발)의 동기화·건강 상태, 운영 앱이 내 브랜치의 끝 커밋을 반영했는지,
# 클러스터가 Git 과 다투고 있지 않은지(20초 동안 Deployment 가 바뀌지 않는지)를 본다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../common/eks.sh"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/functions.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
NS=$APP_NS; DEP=opslab-app
summary() { echo "== 결과: PASS $PASS / FAIL $FAIL =="; [ "$FAIL" -eq 0 ] && { echo "판정: 정상"; exit 0; } || { echo "판정: 비정상"; exit 1; }; }
notready() {  # $1=네임스페이스 [$2=라벨 셀렉터] → Running·Ready 가 아닌 파드(Job 이 만든 파드는 뺀다)
  kubectl -n "$1" get pods ${2:+-l "$2"} -o json 2>/dev/null | jq -r '.items[] | select(.metadata.deletionTimestamp==null)
    | select(.status.phase!="Succeeded" and .status.phase!="Failed") | select((.metadata.ownerReferences[0].kind // "")!="Job")
    | select(.status.phase!="Running" or ([.status.containerStatuses[]?|.ready]|all|not))
    | "\(.metadata.name) \(.status.phase) \([.status.initContainerStatuses[]?,.status.containerStatuses[]? | .state | keys[0] + ":" + ((.waiting.reason // .terminated.reason // "")) ] | join(","))"'
}

verify_main() {
  kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다(kubeconfig)."; exit 2; }
  echo "== $(TZ=Asia/Seoul date '+%F %T') 정상 상태 판정: $SID / $1 =="
  local R B HEAD; R=$(fork_repo); B=$(fork_branch); GH_T=$(gh_token); export GH_T

  echo "[1] 노드"
  local nn nr
  nn=$(kubectl get nodes --no-headers | wc -l); nr=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
  [ "$nn" -ge 2 ] && [ "$nr" -eq "$nn" ] && ok "노드 $nr/$nn Ready" || ng "노드 Ready $nr/$nn (기준: 2대 이상 전부 Ready)"

  echo "[2] 운영 앱 Deployment ($NS/$DEP)"
  local j want upd rdy av tot
  j=$(kubectl -n "$NS" get deploy "$DEP" -o json 2>/dev/null) || { ng "Deployment 가 없습니다 (Argo CD 앱 opslab-prod 가 지워졌거나 동기화되지 않음)"; j=""; }
  if [ -n "$j" ]; then
    read -r want upd rdy av tot <<<"$(jq -r '[.spec.replicas, .status.updatedReplicas//0, .status.readyReplicas//0, .status.availableReplicas//0, .status.replicas//0]|@tsv' <<<"$j")"
    [ "$upd" -eq "$want" ] && [ "$rdy" -eq "$want" ] && [ "$av" -eq "$want" ] && [ "$tot" -eq "$want" ] \
      && ok "배포 완료: 희망 $want = 최신 $upd = Ready $rdy (진행 중인 새 파드 없음)" \
      || ng "배포 미완료: 희망 $want / 최신 $upd / Ready $rdy / 사용 가능 $av / 전체 $tot (kubectl -n $NS rollout status deploy $DEP)"
  fi

  echo "[3] 파드 (app·app-dev·argocd 네임스페이스)"
  local bad x
  bad=$(notready "$NS"; notready app-dev; notready argocd)
  [ -z "$bad" ] && ok "모든 파드 Running·Ready" || { ng "Running·Ready 가 아닌 파드:"; sed 's/^/         /' <<<"$bad"; }
  for x in postgres redis; do
    [ "$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=$x --field-selector=status.phase=Running -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -cw true)" -ge 1 ] \
      && ok "$x Ready" || ng "$x 가 Ready 가 아님"
  done

  echo "[4] Argo CD 구성 요소 (argocd 네임스페이스)"
  local c r w
  for c in deploy/argocd-server deploy/argocd-repo-server statefulset/argocd-application-controller deploy/argocd-redis; do
    r=$(kubectl -n argocd get "$c" -o jsonpath='{.status.readyReplicas}' 2>/dev/null); w=$(kubectl -n argocd get "$c" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    [ "${w:-0}" -ge 1 ] && [ "${r:-0}" -ge "$w" ] && ok "${c#*/} Ready ${r}/${w}" || ng "${c#*/} 가 Ready 가 아님 (Ready ${r:-0}/희망 ${w:-없음})"
  done

  echo "[5] Argo CD 앱 (루트·운영·개발) — 내 Fork ${R:-?} 브랜치 ${B:-?}"
  local a l cond op
  HEAD=$([ -n "$R" ] && gh_head "$R" "$B")
  for a in $APPS; do
    l=$(app_line "$a")
    if [ "$l" = 없음 ]; then ng "$a 앱이 없습니다 (루트 앱이 지웠거나 만들지 못함 — kubectl -n argocd get applications)"; continue; fi
    cond=$(app_json "$a" | jq -r '[.status.conditions[]? | select(.type|test("Error|Warning")) | "\(.type): \(.message|.[0:120])"] | join(" / ")')
    op=$(app_json "$a" | jq -r '.status.operationState | select(.) | "\(.phase): \(.message // "" | .[0:120])"')
    [[ "$l" == "Synced Healthy "* ]] && [ -z "$cond" ] && [[ "$op" != Failed* && "$op" != Error* && "$op" != Running* ]] \
      && ok "$a Synced·Healthy (리비전 ${l:15:7})" \
      || ng "$a 동기화·건강 $(cut -d' ' -f1-2 <<<"$l")${cond:+ — $cond}${op:+ — 마지막 작업 $op}"
  done
  local rev; rev=$(app_json opslab-prod | jq -r '.status.sync.revision // ""')
  [ -n "$HEAD" ] && [ "$rev" = "$HEAD" ] && ok "운영 앱이 브랜치 끝 커밋 ${HEAD:0:7} 을 반영함" \
    || ng "운영 앱 리비전 ${rev:0:7} ≠ 브랜치 끝 커밋 ${HEAD:0:7} (Git 이 반영되지 않음 — Argo CD 앱 상세의 Last Sync·Conditions)"

  echo "[6] Git 과 다투지 않음 (20초 동안 운영 Deployment 가 바뀌지 않는지)"
  local g1 g2; g1=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.generation}' 2>/dev/null); sleep 20
  g2=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.generation}' 2>/dev/null)
  [ -n "$g1" ] && [ "$g1" = "$g2" ] && ok "Deployment 변경 없음(세대 $g2)" || ng "20초 사이 Deployment 가 바뀜(세대 ${g1:-없음} → ${g2:-없음}) — HPA·자동 치유·사람이 서로 되돌리고 있는지"

  echo "[7] 정문(Ingress → ALB → 타깃)"
  local alb tgs tg h n hl
  alb=$(kubectl -n "$NS" get ingress "$DEP" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$alb" ] && ok "Ingress 에 ALB 주소 있음: $alb" || ng "Ingress 에 ALB 주소가 없습니다"
  tgs=$(kubectl -n "$NS" get targetgroupbindings -o jsonpath='{range .items[*]}{.spec.targetGroupARN}{"\n"}{end}' 2>/dev/null)
  if [ -z "$tgs" ]; then ng "타깃 그룹 연결(TargetGroupBinding)이 없습니다"
  else
    for tg in $tgs; do
      h=$(aws elbv2 describe-target-health --target-group-arn "$tg" --query 'TargetHealthDescriptions[].TargetHealth.State' --output text 2>/dev/null)
      h=$(tr '\t' '\n' <<<"$h" | grep -v draining | xargs)
      n=$(wc -w <<<"$h"); hl=$(grep -ow healthy <<<"$h" | wc -l)
      [ "$n" -ge 1 ] && [ "$hl" -eq "$n" ] && ok "ALB 타깃 $hl/$n healthy" || ng "ALB 타깃 healthy $hl/$n (상태: ${h:-없음 — 운영 앱 파드가 없음})"
    done
  fi

  echo "[8] 사용자 경로 (ALB 로 직접 요청 — /health·/db·/cache 각 3회, /api 10회)"
  if [ -n "$alb" ]; then
    local p c k bad2=""
    for p in /health /db /cache /api; do
      k=3; [ "$p" = /api ] && k=10
      for i in $(seq 1 $k); do c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$alb$p"); [ "$c" = 200 ] || { bad2="$bad2 $p=$c"; break; }; done
    done
    [ -z "$bad2" ] && ok "모든 경로 200 응답" || ng "200 이 아닌 경로:$bad2 (502/503=ALB 뒤에 파드가 없음, 500=앱 설정(값)·DB·캐시)"
  else ng "ALB 주소가 없어 사용자 경로를 확인할 수 없음"; fi

  echo "[9] 부하 파드 최근 1분 (ALB 로 초당 10건)"
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
