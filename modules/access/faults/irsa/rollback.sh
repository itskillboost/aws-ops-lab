#!/bin/bash
# access-1 irsa — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
I=$(issuer); A="arn:aws:iam::$ACCT:oidc-provider/$I"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$A" >/dev/null 2>&1; then
  O=$(load oidc); T=$(jq -r '.t[0] // empty' <<<"$O" 2>/dev/null)
  [ -n "$T" ] || T=$(echo | openssl s_client -servername "${I%%/*}" -connect "${I%%/*}:443" -showcerts 2>/dev/null | awk '/BEGIN/{c++} c==4' | sed -n '/BEGIN/,/END/p' | openssl x509 -fingerprint -sha1 -noout 2>/dev/null | sed 's/.*=//; s/://g' | tr A-F a-f)
  aws iam create-open-id-connect-provider --url "https://$I" --client-id-list sts.amazonaws.com --thumbprint-list "${T:-9e99a48a9960b14926bb7f3b02e22da2b0ab7280}" \
    --tags Key=Course,Value=opslab Key=Module,Value=cluster Key=Owner,Value="$SID" >/dev/null && echo "  OIDC 공급자 다시 만듦"
  aws ssm delete-parameter --name "$STATE/oidc" >/dev/null 2>&1
fi
irsa_role "$APP_ROLE" "$NS" opslab-app && echo "  신뢰 정책 복원(app/opslab-app)"
kubectl -n "$NS" annotate sa opslab-app --overwrite eks.amazonaws.com/role-arn="arn:aws:iam::$ACCT:role/$APP_ROLE" >/dev/null && echo "  서비스 계정 어노테이션 복원"
kubectl -n kube-system rollout restart deploy aws-load-balancer-controller >/dev/null 2>&1   # 대행사도 새 자격증명으로
sleep 10; app_restart; app_wait && echo "  앱 배포 완료"
