#!/bin/bash
# workload pod-pending — verify. 실행: bash ~/opslab/modules/workload/faults/pod-pending/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "workload pod-pending"
