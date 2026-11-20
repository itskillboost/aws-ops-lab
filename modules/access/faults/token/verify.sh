#!/bin/bash
# access token — verify. 실행: bash ~/opslab/modules/access/faults/token/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "access token"
