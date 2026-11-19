#!/bin/bash
# workload-5 image-pull — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment 의 이미지 주소, (변형 ③) ECR 풀스루 캐시 규칙 <학번>-workload 와 그 저장소의 정책
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
IMG=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}')
save image "$IMG"
V=$(pick_variant 3)
case $V in
  1) kubectl -n "$NS" set image deploy/"$DEP" app="${IMG%:*}:1.0.1" >/dev/null ;;               # 없는 태그
  2) kubectl -n "$NS" set image deploy/"$DEP" app="${IMG/public.ecr.aws/pubilc.ecr.aws}" >/dev/null ;;   # 레지스트리 주소 오타
  3) # 같은 이미지를 내 계정 ECR(풀스루 캐시)에서 받게 바꾸고, 그 저장소의 정책으로 노드 역할의 읽기를 막는다
     #    (노드 역할 자체의 IAM 정책을 떼면 노드의 인증 토큰 캐시(최대 12시간) 때문에 증상이 바로 안 날 수 있어 저장소 정책으로 분리한다)
     ACCT=$(aws sts get-caller-identity --query Account --output text)
     aws ecr create-pull-through-cache-rule --ecr-repository-prefix "$SID-workload" --upstream-registry-url public.ecr.aws >/dev/null 2>&1 || true   # 이미 있으면 그대로
     P=${IMG#public.ecr.aws/}; REPO="$SID-workload/${P%:*}"
     aws ecr batch-get-image --repository-name "$REPO" --image-ids imageTag="${P##*:}" >/dev/null 2>&1 || true   # 캐시(저장소)를 미리 채운다(내 권한)
     save repo "$REPO"
     NODE_ROLE=$(aws iam get-role --role-name "$SID-cluster-node-role" --query Role.Arn --output text)
     aws ecr set-repository-policy --repository-name "$REPO" --policy-text "$(jq -nc --arg r "$NODE_ROLE" '{Version:"2012-10-17",Statement:[{Sid:"opslab-maintenance",Effect:"Deny",Principal:{AWS:$r},Action:["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"]}]}')" >/dev/null
     kubectl -n "$NS" set image deploy/"$DEP" app="$ACCT.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:${P##*:}" >/dev/null
     # 노드에 이미 받아 둔 이미지가 있어도 매번 레지스트리에 확인하게(재도전 때도 증상이 나도록)
     patch --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' ;;
esac
record $V
