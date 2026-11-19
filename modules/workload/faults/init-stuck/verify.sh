#!/bin/bash
# workload init-stuck — verify. 실행: bash ~/opslab/modules/workload/faults/init-stuck/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "workload init-stuck"
