#!/bin/bash
# podnet-6 sg — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: (변형 ①) aws-node ENABLE_POD_ENI, 실습 태그 보안 그룹 <학번>-podnet-db-sg, app 네임스페이스 SecurityGroupPolicy
#           (변형 ②) 클러스터 보안 그룹의 자기 참조 규칙(노드·파드끼리 통신)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2)
VPC=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.vpcId --output text)
CSG=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
case $V in
  1) # DB 파드에 전용 보안 그룹(파드 보안 그룹)을 붙였는데, 그 보안 그룹이 5432 를 허용하지 않는다
     kubectl -n kube-system set env ds/aws-node ENABLE_POD_ENI=true >/dev/null
     kubectl -n kube-system rollout status ds/aws-node --timeout=5m >/dev/null
     for i in $(seq 1 30); do [ "$(kubectl get nodes -l vpc.amazonaws.com/has-trunk-attached=true --no-headers | wc -l)" -ge 1 ] && break; sleep 10; done
     SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SID-podnet-db-sg" Name=vpc-id,Values="$VPC" --query 'SecurityGroups[0].GroupId' --output text)
     [ "$SG" = None ] && SG=$(aws ec2 create-security-group --group-name "$SID-podnet-db-sg" --description "opslab DB pod SG" --vpc-id "$VPC" \
       --tag-specifications "ResourceType=security-group,Tags=[{Key=Course,Value=opslab},{Key=Module,Value=podnet},{Key=Owner,Value=$SID}]" --query GroupId --output text)
     # 새 보안 그룹은 들어오는 규칙이 하나도 없다(DB 건강검진은 파드 안에서 pg_isready 로 하므로 영향 없음) — 앱에서 오는 5432 가 막힌다
     kubectl apply -f - >/dev/null <<YAML
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata: { name: db-pod-sg, namespace: $NS, labels: { course: opslab } }
spec:
  podSelector: { matchLabels: { app.kubernetes.io/name: postgres } }
  securityGroups: { groupIds: [$SG] }
YAML
     kubectl -n "$NS" delete pod -l app.kubernetes.io/name=postgres --wait=false >/dev/null ;;
  2) # "보안 점검"으로 클러스터 보안 그룹의 자기 참조 규칙(같은 보안 그룹끼리 모두 허용)을 지웠다 → 노드·파드끼리 통신 차단
     R=$(aws ec2 describe-security-group-rules --filters Name=group-id,Values="$CSG" --query "SecurityGroupRules[?!IsEgress && ReferencedGroupInfo.GroupId=='$CSG']" --output json)
     [ "$(jq length <<<"$R")" -ge 1 ] || { echo "자기 참조 규칙을 찾지 못했습니다"; exit 1; }
     save sgrules "$(jq -c '[.[]|{g:.GroupId,s:.ReferencedGroupInfo.GroupId,f:.FromPort,t:.ToPort,p:.IpProtocol}]' <<<"$R")"
     aws ec2 revoke-security-group-ingress --group-id "$CSG" --security-group-rule-ids $(jq -r '.[].SecurityGroupRuleId' <<<"$R") >/dev/null ;;
esac
sleep 10; kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null
record $V
