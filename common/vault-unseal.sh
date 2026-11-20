#!/bin/bash
# Vault 수동 봉인 해제 — Vault 파드가 다시 떠서 봉인(sealed)된 경우. 평소에는 vault-unsealer CronJob 이 1분마다 대신 한다.
#   bash ~/opslab/common/vault-unseal.sh
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/eks.sh"; kube_login
source "$EKS_ROOT/modules/access/functions.sh"
vault_init_unseal && echo "✅ Vault 봉인 해제됨" && vst | jq -c '{initialized,sealed,version}'
