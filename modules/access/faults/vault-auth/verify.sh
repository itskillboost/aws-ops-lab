#!/bin/bash
# access vault-auth — verify. 실행: bash ~/opslab/modules/access/faults/vault-auth/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "access vault-auth"
