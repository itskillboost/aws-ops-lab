#!/bin/bash
# K3 층(인그레스·네트워크 = podnet 모듈 완료 상태) — start.sh 가 실행한다. 다시 실행해도 안전하다.
#   ① Load Balancer Controller 용 IRSA 역할(권한 경계 포함) ② Load Balancer Controller(Helm, Service 가로채기 끔)
#   ③ VPC CNI 네트워크 정책 기능 켜기 ④ Ingress(ALB) ⑤ 기본 NetworkPolicy
# podnet 모듈 1단계 구축 따라하기와 같은 명령이다(modules/podnet/full.sh 도 이 파일을 실행한다).
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../common/eks.sh"
kube_login
K3="$EKS_ROOT/layers/k3-ingress"
ACCT=$(aws sts get-caller-identity --query Account --output text)
ISSUER=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.identity.oidc.issuer --output text | sed 's#^https://##')
VPC=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.vpcId --output text)
POL=$SID-podnet-lbc-policy; ROLE=$SID-podnet-lbc-role
TAGS="Key=Course,Value=opslab Key=Module,Value=podnet Key=Owner,Value=$SID"

# ① IRSA 역할: kube-system/aws-load-balancer-controller 서비스 계정만 이 역할을 빌릴 수 있다
aws iam get-policy --policy-arn "arn:aws:iam::$ACCT:policy/$POL" >/dev/null 2>&1 \
  || aws iam create-policy --policy-name "$POL" --policy-document "file://$EKS_ROOT/modules/podnet/lbc-iam-policy.json" --tags $TAGS >/dev/null \
  || { echo "❌ IAM 정책 $POL 생성 실패"; exit 1; }
sed -e "s/__ACCT__/$ACCT/g" -e "s#__ISSUER__#$ISSUER#g" "$EKS_ROOT/modules/podnet/lbc-trust.json" > /tmp/lbc-trust.json
if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE" --policy-document file:///tmp/lbc-trust.json
else
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document file:///tmp/lbc-trust.json \
    --permissions-boundary "arn:aws:iam::$ACCT:policy/opslab-student-boundary" --tags $TAGS >/dev/null \
    || { echo "❌ IAM 역할 $ROLE 생성 실패"; exit 1; }
fi
aws iam attach-role-policy --role-name "$ROLE" --policy-arn "arn:aws:iam::$ACCT:policy/$POL"
echo "  IRSA 역할 $ROLE"

# ② Load Balancer Controller — 이미지·차트는 미러·고정 차트만 쓴다. LoadBalancer Service 는 가로채지 않는다(Headlamp NLB 를 지키기 위해)
helm upgrade --install aws-load-balancer-controller "$EKS_ROOT/vendor/charts/aws-load-balancer-controller" -n kube-system --wait --timeout 10m \
  --set clusterName="$CLUSTER" --set region="$AWS_REGION" --set vpcId="$VPC" \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::$ACCT:role/$ROLE" \
  --set image.repository="$(img_repo lbc)" --set image.tag="$(img_tag lbc)" \
  --set enableServiceMutatorWebhook=false \
  --set defaultTags.Course=opslab --set defaultTags.Module=podnet --set defaultTags.Owner="$SID" >/dev/null \
  || { echo "❌ Load Balancer Controller 설치 실패"; exit 1; }
echo "  Load Balancer Controller"

# ③ VPC CNI 네트워크 정책 기능(파드 출입문 규칙을 실제로 적용하는 부품)
if [ "$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name vpc-cni --query addon.configurationValues --output text 2>/dev/null | grep -c enableNetworkPolicy)" -eq 0 ]; then
  aws eks update-addon --cluster-name "$CLUSTER" --addon-name vpc-cni --resolve-conflicts OVERWRITE \
    --configuration-values '{"enableNetworkPolicy":"true"}' >/dev/null || { echo "❌ VPC CNI 설정 변경 실패"; exit 1; }
  sleep 10; aws eks wait addon-active --cluster-name "$CLUSTER" --addon-name vpc-cni
fi
kubectl -n kube-system rollout status ds/aws-node --timeout=5m >/dev/null
echo "  VPC CNI 네트워크 정책"

# ④ Ingress(ALB) ⑤ 기본 NetworkPolicy
sed "s/__SID__/$SID/g" "$K3/ingress.yaml" | kubectl apply -f - >/dev/null
kubectl apply -f "$K3/netpol.yaml" >/dev/null
for i in $(seq 1 40); do
  ALB=$(kubectl -n "$APP_NS" get ingress opslab-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  [ -n "$ALB" ] && curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$ALB/health" | grep -q 200 && break; sleep 15
done
[ -n "${ALB:-}" ] || { echo "❌ Ingress 에 ALB 주소가 생기지 않음 — kubectl -n $APP_NS describe ingress opslab-app"; exit 1; }
grep -q "^export ALB_DNS=" ~/opslab-env.sh 2>/dev/null && sed -i "s#^export ALB_DNS=.*#export ALB_DNS=$ALB#" ~/opslab-env.sh || echo "export ALB_DNS=$ALB" >> ~/opslab-env.sh
echo "  Ingress(ALB) http://$ALB"
echo "  NetworkPolicy db-allow-app"
