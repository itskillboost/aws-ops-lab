#!/bin/bash
# cluster node-notready — verify. 실행: bash ~/opslab/modules/cluster/faults/node-notready/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "cluster node-notready"
