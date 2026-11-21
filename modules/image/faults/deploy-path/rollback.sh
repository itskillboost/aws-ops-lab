#!/bin/bash
# image-4 deploy-path — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
gh_api DELETE "/repos/$R/git/refs/heads/opslab/image-old" >/dev/null 2>&1 && echo "  장애용 브랜치 opslab/image-old 삭제"
aws secretsmanager delete-secret --secret-id "$SID-image-old-token" --force-delete-without-recovery >/dev/null 2>&1 && echo "  장애용 시크릿 $SID-image-old-token 삭제"
restore
