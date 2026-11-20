#!/bin/bash
# access-5 token — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl -n vault delete secret vault-reviewer-token --ignore-not-found >/dev/null
vault_configure && echo "  Vault Kubernetes Auth 설정 복원(Vault 자신의 서비스 계정 토큰 사용)"
kubectl -n "$NS" patch sa opslab-app --type json -p '[{"op":"remove","path":"/automountServiceAccountToken"}]' >/dev/null 2>&1 && echo "  서비스 계정 토큰 자동 마운트 복원"
app_restart; app_wait && echo "  앱 배포 완료"
