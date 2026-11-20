#!/bin/bash
# podnet netpol — verify. 실행: bash ~/opslab/modules/podnet/faults/netpol/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "podnet netpol"
