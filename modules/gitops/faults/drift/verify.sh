#!/bin/bash
# gitops drift — verify. 실행: bash ~/opslab/modules/gitops/faults/drift/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "gitops drift"
