#!/bin/bash
# access-5 token — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl -n vault delete secret vault-reviewer-token --ignore-not-found >/dev/null
vault_configure && echo "  Vault Kubernetes Auth 설정·역할 복원(리뷰어 토큰 없음·audience 없음)"
app_restart; app_wait && echo "  앱 배포 완료"
