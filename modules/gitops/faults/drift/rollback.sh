#!/bin/bash
# gitops-2 drift — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
restore_branch    # 브랜치를 주입 전 커밋으로 → 자동 치유가 다시 켜지고, 수동으로 바꾼 값은 Git 값으로 되돌아간다
