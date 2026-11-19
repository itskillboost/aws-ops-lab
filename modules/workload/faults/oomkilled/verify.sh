#!/bin/bash
# workload oomkilled — verify. 실행: bash ~/opslab/modules/workload/faults/oomkilled/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "workload oomkilled"
