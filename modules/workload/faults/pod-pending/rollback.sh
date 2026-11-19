#!/bin/bash
# workload-1 pod-pending — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
kubectl taint nodes --all opslab/maintenance- >/dev/null 2>&1 && echo "  노드 taint 제거" || echo "  노드 taint 없음"
helm_restore
