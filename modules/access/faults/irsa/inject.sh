#!/bin/bash
# access-1 irsa — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app 서비스 계정 어노테이션(①), IAM 역할 <학번>-access-app-role 의 신뢰 정책(②), 이 클러스터의 OIDC 공급자(③)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # 서비스 계정에 적은 역할 ARN 오타("role" → "rol") — 없는 역할을 빌리려 한다
     kubectl -n "$NS" annotate sa opslab-app --overwrite eks.amazonaws.com/role-arn="arn:aws:iam::$ACCT:role/${APP_ROLE%e}" >/dev/null ;;
  2) # 신뢰 정책의 서비스 계정 조건이 다른 이름(opslab-api) — 역할은 있지만 이 파드에게는 빌려주지 않는다
     irsa_trust "$NS" opslab-api > /tmp/trust-bad.json
     aws iam update-assume-role-policy --role-name "$APP_ROLE" --policy-document file:///tmp/trust-bad.json ;;
  3) # OIDC 공급자(신원 확인 창구) 삭제 — "정리 작업"으로 지워졌다. 원복용으로 주소·지문을 저장한다
     I=$(issuer); A="arn:aws:iam::$ACCT:oidc-provider/$I"
     save oidc "$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$A" --query '{u:Url,c:ClientIDList,t:ThumbprintList}' --output json | jq -c .)"
     aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$A" ;;
esac
sleep 5; app_restart   # 새 파드가 새 자격증명을 받으면서 증상이 드러난다
record $V
