#!/bin/bash
# podnet-6 sg — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
R=$(load sgrules)
if [ -n "$R" ] && [ "$R" != None ]; then
  for x in $(jq -c '.[]' <<<"$R"); do
    p=$(jq -r .p <<<"$x"); perm="IpProtocol=$p,UserIdGroupPairs=[{GroupId=$(jq -r .s <<<"$x")}]"
    [ "$p" != "-1" ] && perm="IpProtocol=$p,FromPort=$(jq -r .f <<<"$x"),ToPort=$(jq -r .t <<<"$x"),UserIdGroupPairs=[{GroupId=$(jq -r .s <<<"$x")}]"
    aws ec2 authorize-security-group-ingress --group-id "$(jq -r .g <<<"$x")" --ip-permissions "$perm" >/dev/null 2>&1 && echo "  클러스터 보안 그룹 규칙 복원"
  done
  aws ssm delete-parameter --name "$STATE/sgrules" >/dev/null 2>&1
fi
if kubectl -n "$NS" get securitygrouppolicy db-pod-sg >/dev/null 2>&1; then
  kubectl -n "$NS" delete securitygrouppolicy db-pod-sg >/dev/null && echo "  SecurityGroupPolicy 삭제"
  kubectl -n "$NS" delete pod -l app.kubernetes.io/name=postgres >/dev/null
fi
kubectl -n "$NS" rollout status statefulset postgres --timeout=5m >/dev/null
VPC=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.vpcId --output text)
SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-podnet-db-sg" Name=vpc-id,Values="$VPC" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG" != None ]; then
  for i in $(seq 1 18); do aws ec2 delete-security-group --group-id "$SG" 2>/dev/null && { echo "  보안 그룹 $SID-podnet-db-sg 삭제"; break; }; sleep 10; done
fi
if kubectl -n kube-system get ds aws-node -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_POD_ENI")].value}' | grep -q true; then
  kubectl -n kube-system set env ds/aws-node ENABLE_POD_ENI=false >/dev/null && kubectl -n kube-system rollout status ds/aws-node --timeout=5m >/dev/null && echo "  aws-node ENABLE_POD_ENI=false"
fi
kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null; kubectl -n "$NS" rollout status deploy "$DEP" --timeout=5m >/dev/null && echo "  앱 배포 완료"
