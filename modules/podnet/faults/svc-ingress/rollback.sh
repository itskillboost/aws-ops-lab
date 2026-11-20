#!/bin/bash
# podnet-2 svc-ingress — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
app_restore
ingress_restore
wait_alb_healthy && echo "  ALB 로 /health 200 확인" || echo "  ⚠️ ALB 응답이 아직 정상이 아님"
