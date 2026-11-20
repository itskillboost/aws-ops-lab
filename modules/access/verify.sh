#!/bin/bash
# access 모듈 정상 상태 판정 공통 — baseline/verify.sh 와 faults/*/verify.sh 가 source 한다.
#   verify_main "<제목>"  → PASS/FAIL 을 출력하고 종료 코드(0=정상)로 끝낸다
# 노드·앱·파드에 더해, Vault(금고) 상태·비밀 주입, IRSA(파드의 AWS 신원), RBAC(dev 역할) 를 본다. 축출·완료된 옛 파드 기록은 보지 않는다.
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

  echo "[1] 노드"
  local nn nr
  nn=$(kubectl get nodes --no-headers | wc -l); nr=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
  [ "$nn" -ge 2 ] && [ "$nr" -eq "$nn" ] && ok "노드 $nr/$nn Ready" || ng "노드 Ready $nr/$nn (기준: 2대 이상 전부 Ready)"

  echo "[2] 샘플 앱 Deployment ($NS/$DEP)"
  local j want upd rdy av tot
  j=$(kubectl -n "$NS" get deploy "$DEP" -o json) || { ng "Deployment 없음"; summary; }
  read -r want upd rdy av tot <<<"$(jq -r '[.spec.replicas, .status.updatedReplicas//0, .status.readyReplicas//0, .status.availableReplicas//0, .status.replicas//0]|@tsv' <<<"$j")"
  [ "$upd" -eq "$want" ] && [ "$rdy" -eq "$want" ] && [ "$av" -eq "$want" ] && [ "$tot" -eq "$want" ] \
    && ok "배포 완료: 희망 $want = 최신 $upd = Ready $rdy (진행 중인 새 파드 없음)" \
    || ng "배포 미완료: 희망 $want / 최신 $upd / Ready $rdy / 사용 가능 $av / 전체 $tot (kubectl rollout status)"

  echo "[3] 파드 ($NS·vault 네임스페이스)"
  local bad x
  bad=$(kubectl -n "$NS" get pods -o json | jq -r '.items[] | select(.metadata.deletionTimestamp==null) | select(.status.phase!="Succeeded" and .status.phase!="Failed") |
        select(.status.phase!="Running" or ([.status.containerStatuses[]?|.ready]|all|not)) |
        "\(.metadata.name) \(.status.phase) \([.status.initContainerStatuses[]?,.status.containerStatuses[]? | .state | keys[0] + ":" + ((.waiting.reason // .terminated.reason // "") )] | join(","))"')
  [ -z "$bad" ] && ok "모든 파드 Running·Ready (Pending·ContainerCreating 0개)" || { ng "Running·Ready 가 아닌 파드:"; sed 's/^/         /' <<<"$bad"; }
  for x in postgres redis; do
    [ "$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=$x --field-selector=status.phase=Running -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -cw true)" -ge 1 ] \
      && ok "$x Ready" || ng "$x 가 Ready 가 아님"
  done
  local vb; vb=$(kubectl -n vault get pods -o json | jq -r '.items[] | select(.metadata.deletionTimestamp==null) | select(.status.phase!="Succeeded" and .status.phase!="Failed") | select((.metadata.ownerReferences[0].kind // "")!="Job") |
        select(.status.phase!="Running" or ([.status.containerStatuses[]?|.ready]|all|not)) | "\(.metadata.name) \(.status.phase)"')
  [ -z "$vb" ] && ok "vault 네임스페이스 파드 모두 Running·Ready (vault-0·injector)" || { ng "vault 네임스페이스에 Ready 가 아닌 파드:"; sed 's/^/         /' <<<"$vb"; }
  local sc; sc=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=opslab-app -o json | jq -r '[.items[] | select(.metadata.deletionTimestamp==null)] | "\(map(select([.spec.containers[].name]|index("vault-agent"))) | length) \(length)"')
  [ "${sc% *}" -ge 1 ] && [ "${sc% *}" = "${sc#* }" ] && ok "앱 파드 모두 Vault Agent 사이드카 주입됨(${sc% *}/${sc#* })" || ng "Vault Agent 사이드카가 없는 앱 파드가 있습니다(${sc% *}/${sc#* } 주입) — 주입기·어노테이션 확인"

  echo "[4] Vault(금고)"
  local st; st=$(vst)
  [ "$(jq -r .sealed 2>/dev/null <<<"$st")" = false ] && ok "Vault 봉인 해제됨(unsealed)" || ng "Vault 가 봉인돼 있거나 응답하지 않습니다 (kubectl -n vault exec vault-0 -- vault status)"
  local inj; inj=$(kubectl -n vault get deploy vault-agent-injector -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${inj:-0}" -ge 1 ] && ok "Agent Injector(사이드카 주입기) Ready" || ng "Agent Injector 가 Ready 가 아님"

  echo "[5] 정문(Ingress → ALB → 타깃)"
  local alb tgs tg h n hl
  alb=$(kubectl -n "$NS" get ingress "$DEP" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$alb" ] && ok "Ingress 에 ALB 주소 있음: $alb" || ng "Ingress 에 ALB 주소가 없습니다 (kubectl -n $NS describe ingress $DEP 의 Events)"
  tgs=$(kubectl -n "$NS" get targetgroupbindings -o jsonpath='{range .items[*]}{.spec.targetGroupARN}{"\n"}{end}' 2>/dev/null)
  if [ -z "$tgs" ]; then ng "타깃 그룹 연결(TargetGroupBinding)이 없습니다"
  else
    for tg in $tgs; do
      h=$(aws elbv2 describe-target-health --target-group-arn "$tg" --query 'TargetHealthDescriptions[].TargetHealth.State' --output text 2>/dev/null)
      h=$(tr '\t' '\n' <<<"$h" | grep -v draining | xargs)   # draining: 교체돼 빠지는 중인 옛 파드 — 판정에서 뺀다
      n=$(wc -w <<<"$h"); hl=$(grep -ow healthy <<<"$h" | wc -l)
      [ "$n" -ge 1 ] && [ "$hl" -eq "$n" ] && ok "ALB 타깃 $hl/$n healthy" || ng "ALB 타깃 healthy $hl/$n (상태: ${h:-없음})"
    done
  fi

  echo "[6] 사용자 경로 (ALB 로 직접 요청 — /health·/api·/db·/cache 각 3회, /aws 의 IRSA 신원)"
  if [ -n "$alb" ]; then
    local p c bad2=""
    for p in /health /api /db /cache; do
      for i in 1 2 3; do c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$alb$p"); [ "$c" = 200 ] || { bad2="$bad2 $p=$c"; break; }; done
    done
    [ -z "$bad2" ] && ok "모든 경로 200 응답" || ng "200 이 아닌 경로:$bad2 (000=연결 실패, 502/503/504=ALB 뒤가 문제, 500=앱 안쪽(DB·캐시·DNS))"
    local aw; aw=$(curl -s -m 10 "http://$alb/aws")
    grep -q "assumed-role/$APP_ROLE/" <<<"$aw" && ok "/aws: 앱이 IRSA 역할 $APP_ROLE 로 AWS 를 부름" \
      || ng "/aws 가 IRSA 역할이 아님: $(jq -r '.arn // .message // empty' <<<"$aw" 2>/dev/null | cut -c1-160)"
  else ng "ALB 주소가 없어 사용자 경로를 확인할 수 없음"; fi

  echo "[7] RBAC — 개발자 역할($DEV_ROLE → 그룹 opslab-dev)"
  local r1 r2
  r1=$(dev_kubectl auth can-i list pods -n "$NS" 2>/dev/null); r2=$(dev_kubectl auth can-i patch deployments -n "$NS" 2>/dev/null)
  [ "$r1" = yes ] && [ "$r2" = yes ] && ok "dev 가 app 네임스페이스에서 파드 조회·배포 재시작 가능" || ng "dev 권한 부족: 파드 조회=${r1:-오류} 배포 재시작=${r2:-오류} (kubectl auth can-i … --as)"

  echo "[8] 부하 파드 최근 1분 (ALB 로 초당 10건)"
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
