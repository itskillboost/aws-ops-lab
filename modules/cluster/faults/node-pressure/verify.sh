#!/bin/bash
# cluster node-pressure — verify. 실행: bash ~/opslab/modules/cluster/faults/node-pressure/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "cluster node-pressure"
