#!/bin/bash
# workload image-pull — verify. 실행: bash ~/opslab/modules/workload/faults/image-pull/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "workload image-pull"
