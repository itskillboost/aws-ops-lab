#!/bin/bash
# access-3 inject — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl -n vault scale deploy vault-agent-injector --replicas=1 >/dev/null && kubectl -n vault rollout status deploy vault-agent-injector --timeout=3m >/dev/null && echo "  Agent Injector 1개"
vault_configure && echo "  Vault 정책 opslab-app 복원"
app_restore
