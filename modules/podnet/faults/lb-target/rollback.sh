#!/bin/bash
# podnet-3 lb-target — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
R=$(load sgrules)
if [ -n "$R" ] && [ "$R" != None ]; then
  for x in $(jq -c '.[]' <<<"$R"); do
    aws ec2 authorize-security-group-ingress --group-id "$(jq -r .g <<<"$x")" --ip-permissions "IpProtocol=$(jq -r .p <<<"$x"),FromPort=$(jq -r .f <<<"$x"),ToPort=$(jq -r .t <<<"$x"),UserIdGroupPairs=[{GroupId=$(jq -r .s <<<"$x")}]" >/dev/null 2>&1 && echo "  보안 그룹 규칙 복원"
  done
  aws ssm delete-parameter --name "$STATE/sgrules" >/dev/null 2>&1
fi
app_restore
kubectl -n "$NS" annotate ingress "$DEP" alb.ingress.kubernetes.io/healthcheck-port- >/dev/null 2>&1   # apply 로는 덧붙인 어노테이션이 지워지지 않는다
ingress_restore
wait_alb_healthy && echo "  ALB 로 /health 200 확인" || echo "  ⚠️ ALB 응답이 아직 정상이 아님"
