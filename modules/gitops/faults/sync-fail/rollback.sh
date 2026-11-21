#!/bin/bash
# gitops-3 sync-fail — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
restore_branch    # 멈춘 동기화 작업을 끝내고(terminate), 브랜치를 주입 전 커밋으로 되돌려 다시 동기화한다
