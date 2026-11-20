#!/bin/bash
# podnet ip-exhaust — verify. 실행: bash ~/opslab/modules/podnet/faults/ip-exhaust/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "podnet ip-exhaust"
