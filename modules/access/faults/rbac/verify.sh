#!/bin/bash
# access rbac — verify. 실행: bash ~/opslab/modules/access/faults/rbac/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "access rbac"
