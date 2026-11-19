#!/bin/bash
# workload-5 image-pull — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment 의 이미지 주소, (변형 ③) ECR 풀스루 캐시 규칙 <학번>-workload·노드 역할의 ECR 읽기 정책 분리
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
IMG=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}')
save image "$IMG"
V=$(pick_variant 3)
case $V in
  1) kubectl -n "$NS" set image deploy/"$DEP" app="${IMG%:*}:1.0.1" >/dev/null ;;               # 없는 태그
  2) kubectl -n "$NS" set image deploy/"$DEP" app="${IMG/public.ecr.aws/pubilc.ecr.aws}" >/dev/null ;;   # 레지스트리 주소 오타
  3) # 같은 이미지를 내 계정 ECR(풀스루 캐시)로 받게 바꾸고, 노드 역할에서 ECR 읽기 정책을 뗀다
     ACCT=$(aws sts get-caller-identity --query Account --output text)
     aws ecr create-pull-through-cache-rule --ecr-repository-prefix "$SID-workload" --upstream-registry-url public.ecr.aws >/dev/null 2>&1 || true   # 이미 있으면 그대로
     P=${IMG#public.ecr.aws/}; REPO="$SID-workload/${P%:*}"
     aws ecr batch-get-image --repository-name "$REPO" --image-ids imageTag="${P##*:}" >/dev/null 2>&1 || true   # 캐시를 미리 채운다(내 권한)
     ROLE=$SID-cluster-node-role
     aws iam detach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
     kubectl -n "$NS" set image deploy/"$DEP" app="$ACCT.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:${P##*:}" >/dev/null ;;
esac
record $V
