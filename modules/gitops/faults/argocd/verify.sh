#!/bin/bash
# gitops argocd — verify. 실행: bash ~/opslab/modules/gitops/faults/argocd/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "gitops argocd"
