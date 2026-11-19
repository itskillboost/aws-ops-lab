#!/bin/bash
# workload crashloop — verify. 실행: bash ~/opslab/modules/workload/faults/crashloop/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "workload crashloop"
