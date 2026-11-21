#!/bin/bash
# gitops env-values — verify. 실행: bash ~/opslab/modules/gitops/faults/env-values/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "gitops env-values"
