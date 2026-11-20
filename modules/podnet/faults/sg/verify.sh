#!/bin/bash
# podnet sg — verify. 실행: bash ~/opslab/modules/podnet/faults/sg/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "podnet sg"
