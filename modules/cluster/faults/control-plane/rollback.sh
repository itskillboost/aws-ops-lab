#!/bin/bash
# cluster-3 control-plane — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
ARN=$(load node_role)
if [ -n "$ARN" ] && [ "$ARN" != None ]; then
  aws eks describe-access-entry --cluster-name "$CLUSTER" --principal-arn "$ARN" >/dev/null 2>&1 \
    || { aws eks create-access-entry --cluster-name "$CLUSTER" --principal-arn "$ARN" --type EC2_LINUX >/dev/null && echo "  노드 역할 접근 항목 복구"; }
  N=$(load node); sleep 10
  [ -n "$N" ] && [ "$N" != None ] && on_node "$N" "systemctl restart kubelet" >/dev/null
  kubectl wait --for=condition=Ready nodes --all --timeout=240s >/dev/null && echo "  노드 모두 Ready" || echo "  ⚠️ Ready 가 아닌 노드가 있습니다"
fi
kubectl uncordon $(kubectl get nodes -o name) >/dev/null 2>&1 && echo "  노드 스케줄 금지 해제"
kubectl delete clusterrolebinding,clusterrole opslab-night-maint --ignore-not-found >/dev/null
kubectl -n app delete sa night-maint --ignore-not-found >/dev/null
kubectl -n "$NS" rollout status deploy "$DEP" --timeout=180s >/dev/null && echo "  앱 배포 완료"
true
