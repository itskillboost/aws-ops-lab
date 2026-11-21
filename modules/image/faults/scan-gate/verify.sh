#!/bin/bash
# image scan-gate — verify. 실행: bash ~/opslab/modules/image/faults/scan-gate/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "image scan-gate"
