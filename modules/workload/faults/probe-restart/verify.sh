#!/bin/bash
# workload probe-restart — verify. 실행: bash ~/opslab/modules/workload/faults/probe-restart/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "workload probe-restart"
