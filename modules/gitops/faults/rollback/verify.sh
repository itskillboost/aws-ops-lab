#!/bin/bash
# gitops rollback — verify. 실행: bash ~/opslab/modules/gitops/faults/rollback/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "gitops rollback"
