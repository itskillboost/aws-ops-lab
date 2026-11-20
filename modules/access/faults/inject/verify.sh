#!/bin/bash
# access inject — verify. 실행: bash ~/opslab/modules/access/faults/inject/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "access inject"
