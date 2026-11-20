#!/bin/bash
# podnet svc-ingress — verify. 실행: bash ~/opslab/modules/podnet/faults/svc-ingress/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "podnet svc-ingress"
