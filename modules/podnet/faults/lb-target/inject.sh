#!/bin/bash
# podnet-3 lb-target — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Ingress 어노테이션(변형 ①③), 클러스터 보안 그룹의 ALB 허용 규칙(변형 ②)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
ann() { kubectl -n "$NS" annotate ingress "$DEP" --overwrite "$@" >/dev/null; }
case $V in
  1) ann alb.ingress.kubernetes.io/healthcheck-path=/healthz ;;                       # 앱에 없는 건강검진 경로
  2) # ALB → 파드(8080) 를 허용하던 클러스터 보안 그룹 규칙을 지운다("보안 점검에서 정리")
     CSG=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
     P=$(aws ec2 describe-security-group-rules --filters Name=group-id,Values="$CSG" --query "SecurityGroupRules[?!IsEgress && ReferencedGroupInfo.GroupId && FromPort==\`8080\`]" --output json)
     [ "$(jq length <<<"$P")" -ge 1 ] || { echo "ALB 허용 규칙(8080)을 찾지 못했습니다"; exit 1; }
     save sgrules "$(jq -c '[.[]|{g:.GroupId,s:.ReferencedGroupInfo.GroupId,f:.FromPort,t:.ToPort,p:.IpProtocol}]' <<<"$P")"
     aws ec2 revoke-security-group-ingress --group-id "$CSG" --security-group-rule-ids $(jq -r '.[].SecurityGroupRuleId' <<<"$P") >/dev/null ;;
  3) # 타깃 유형을 instance 로 바꿨는데 Service 는 ClusterIP 그대로(instance 는 NodePort 가 필요)
     ann alb.ingress.kubernetes.io/target-type=instance ;;
esac
record $V
