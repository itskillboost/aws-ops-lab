#!/bin/bash
# podnet coredns — verify. 실행: bash ~/opslab/modules/podnet/faults/coredns/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "podnet coredns"
