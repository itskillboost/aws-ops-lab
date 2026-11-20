#!/bin/bash
# cluster control-plane — verify. 실행: bash ~/opslab/modules/cluster/faults/control-plane/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "cluster control-plane"
