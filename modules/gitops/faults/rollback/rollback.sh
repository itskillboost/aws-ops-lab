#!/bin/bash
# gitops-4 rollback — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
restore_branch    # 브랜치를 주입 전 커밋으로 → 루트 앱이 운영 앱을 다시 만들고, 운영 앱이 샘플 앱을 다시 배포한다
