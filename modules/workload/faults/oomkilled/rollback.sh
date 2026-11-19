#!/bin/bash
# workload-3 oomkilled — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
kubectl -n "$NS" delete limitrange app-defaults --ignore-not-found >/dev/null && echo "  LimitRange app-defaults 정리"
helm_restore
