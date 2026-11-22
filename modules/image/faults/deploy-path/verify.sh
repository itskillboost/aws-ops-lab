#!/bin/bash
# image deploy-path — verify. 실행: bash ~/opslab/modules/image/faults/deploy-path/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "image deploy-path"
