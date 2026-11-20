#!/bin/bash
# podnet lb-target — verify. 실행: bash ~/opslab/modules/podnet/faults/lb-target/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "podnet lb-target"
