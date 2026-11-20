#!/bin/bash
# cluster-2 node-pressure — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl -n "$NS" delete deploy opslab-batch --ignore-not-found --wait=true --timeout=120s >/dev/null && echo "  배치 Deployment 삭제"
N=$(load node); [ -n "$N" ] && [ "$N" != None ] || N=$(target_node)
on_node "$N" "rm -f /var/log/app-core.dump; df -h / | tail -1" | sed 's/^/  디스크: /'
echo "  압박 상태가 풀리기를 기다립니다(kubelet 은 압박이 사라진 뒤 5분 동안 상태를 유지한다)"
for i in $(seq 1 50); do
  p=$(kubectl get node "$N" -o json | jq '[.status.conditions[]|select((.type|test("Pressure")) and .status=="True")]|length')
  [ "$p" -eq 0 ] && break; sleep 10
done
[ "$p" -eq 0 ] && echo "  노드 $N 압박 해제" || echo "  ⚠️ 노드 $N 압박 상태가 아직 남아 있습니다(몇 분 뒤 다시 verify)"
# 축출된(Failed) 파드 기록 정리
kubectl -n "$NS" delete pods --field-selector=status.phase=Failed >/dev/null 2>&1
kubectl -n "$NS" rollout status deploy "$DEP" --timeout=300s >/dev/null && echo "  앱 배포 정상"
true
