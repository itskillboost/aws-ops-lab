#!/bin/bash
# gitops sync-fail — verify. 실행: bash ~/opslab/modules/gitops/faults/sync-fail/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "gitops sync-fail"
