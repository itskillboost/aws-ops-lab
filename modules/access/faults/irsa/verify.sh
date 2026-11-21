#!/bin/bash
# access irsa — verify. 실행: bash ~/opslab/modules/access/faults/irsa/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "access irsa"
