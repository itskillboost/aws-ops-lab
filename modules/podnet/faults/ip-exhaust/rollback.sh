#!/bin/bash
# podnet-1 ip-exhaust — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl -n "$NS" delete deploy opslab-batch --ignore-not-found >/dev/null && echo "  배치 Deployment 삭제"
for e in $(aws ec2 describe-network-interfaces --filters Name=tag:Owner,Values="$SID" "Name=tag:Name,Values=$SID-legacy-batch" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text); do
  aws ec2 delete-network-interface --network-interface-id "$e" && echo "  ENI 삭제 $e"; done
if kubectl -n kube-system get ds aws-node -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' | grep -qw MAX_ENI; then
  kubectl -n kube-system set env ds/aws-node MAX_ENI- >/dev/null && kubectl -n kube-system rollout status ds/aws-node --timeout=5m >/dev/null && echo "  aws-node MAX_ENI 제거"
fi
kubectl -n "$NS" rollout status deploy "$DEP" --timeout=5m >/dev/null && echo "  앱 배포 완료"
