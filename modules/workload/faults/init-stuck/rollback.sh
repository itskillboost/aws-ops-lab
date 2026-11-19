#!/bin/bash
# workload-6 init-stuck — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
helm_restore
