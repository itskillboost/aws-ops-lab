#!/bin/bash
# podnet-5 netpol — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl -n "$NS" delete networkpolicy default-deny-ingress app-egress --ignore-not-found >/dev/null && echo "  추가된 NetworkPolicy 삭제"
kubectl replace --force -f "$K3/netpol.yaml" >/dev/null && echo "  db-allow-app 기준 상태로 복원"
wait_alb_healthy && echo "  ALB 로 /health 200 확인" || echo "  ⚠️ ALB 응답이 아직 정상이 아님"
