#!/bin/bash
# cluster 모듈 정상 상태 판정 공통 (workload 판정에 노드 상태 조건을 더하고, 앱 재시작 횟수와 이미 끝난(축출된) 파드 기록은 보지 않는다) — baseline/verify.sh 와 faults/*/verify.sh 가 source 한다.
#   verify_main "<제목>"  → PASS/FAIL 을 출력하고 종료 코드(0=정상)로 끝낸다
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../common/eks.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
NS=$APP_NS; DEP=opslab-app

verify_main() {
  kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다(kubeconfig)."; exit 2; }
  echo "== $(TZ=Asia/Seoul date '+%F %T') 정상 상태 판정: $SID / $1 =="

  echo "[1] 노드"
  local nn nr tn
  nn=$(kubectl get nodes --no-headers | wc -l)
  nr=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
  [ "$nn" -ge 2 ] && [ "$nr" -eq "$nn" ] && ok "노드 $nr/$nn Ready" || ng "노드 Ready $nr/$nn (기준: 2대 이상 전부 Ready)"
  local pr un
  pr=$(kubectl get nodes -o json | jq -r '.items[] | .metadata.name as $n | .status.conditions[] | select(.type!="Ready" and .status=="True" and (.type|test("Pressure|Unavailable"))) | "\($n) \(.type)"')
  [ -z "$pr" ] && ok "노드 자원 압박 없음(Memory·Disk·PID Pressure 모두 False)" || { ng "자원 압박 상태인 노드:"; sed 's/^/         /' <<<"$pr"; }
  un=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.unschedulable==true) | .metadata.name')
  [ -z "$un" ] && ok "스케줄 금지(cordon)된 노드 없음" || ng "cordon 된 노드: $(echo $un)"

  echo "[2] 샘플 앱 Deployment ($NS/$DEP)"
  local j want upd rdy av tot
  j=$(kubectl -n "$NS" get deploy "$DEP" -o json) || { ng "Deployment 없음"; summary; }
  read -r want upd rdy av tot <<<"$(jq -r '[.spec.replicas, .status.updatedReplicas//0, .status.readyReplicas//0, .status.availableReplicas//0, .status.replicas//0]|@tsv' <<<"$j")"
  [ "$upd" -eq "$want" ] && [ "$rdy" -eq "$want" ] && [ "$av" -eq "$want" ] && [ "$tot" -eq "$want" ] \
    && ok "배포 완료: 희망 $want = 최신 $upd = Ready $rdy (진행 중인 새 파드 없음)" \
    || ng "배포 미완료: 희망 $want / 최신 $upd / Ready $rdy / 사용 가능 $av / 전체 $tot (kubectl rollout status)"

  echo "[3] 파드 ($NS 네임스페이스)"
  local bad
  bad=$(kubectl -n "$NS" get pods -o json | jq -r '.items[] | select(.metadata.deletionTimestamp==null) | select(.status.phase!="Succeeded" and .status.phase!="Failed") |
        select(.status.phase!="Running" or ([.status.containerStatuses[]?|.ready]|all|not)) |
        "\(.metadata.name) \(.status.phase) \([.status.initContainerStatuses[]?,.status.containerStatuses[]? | .state | keys[0] + ":" + ((.waiting.reason // .terminated.reason // "") )] | join(","))"')
  [ -z "$bad" ] && ok "모든 파드 Running·Ready (Pending 0개)" || { ng "Running·Ready 가 아닌 파드:"; sed 's/^/         /' <<<"$bad"; }
  for x in postgres redis; do
    [ "$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=$x -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)" = true ] \
      && ok "$x Ready" || ng "$x 가 Ready 가 아님"
  done

  echo "[4] 사용자 응답 (부하 파드 최근 1분)"
  local lines e5 ce req avg
  lines=$(kubectl -n "$NS" logs deploy/opslab-load --since=70s 2>/dev/null | grep 'req=' | tail -6)
  if [ -z "$lines" ]; then ng "요청 수 0건 — 부하 파드가 없습니다: bash ~/opslab/common/load.sh pod"
  else
    req=$(grep -o 'req=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    e5=$(grep -o '5xx=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    ce=$(grep -o 'conn_err=[0-9]*' <<<"$lines" | cut -d= -f2 | awk '{s+=$1}END{print s+0}')
    avg=$(grep -o 'avg_ms=[0-9]*' <<<"$lines" | cut -d= -f2 | sort -n | tail -1)
    [ "$e5" -eq 0 ] && [ "$ce" -eq 0 ] && ok "요청 $req건 중 5xx 0건·연결 오류 0건" || ng "요청 $req건 중 5xx $e5건·연결 오류 $ce건 (기준 0건)"
    [ "$avg" -le 200 ] && ok "평균 응답시간 최대 ${avg}ms (기준 200ms 이하)" || ng "평균 응답시간 최대 ${avg}ms (기준 200ms 이하)"
  fi
  summary
}
summary() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
