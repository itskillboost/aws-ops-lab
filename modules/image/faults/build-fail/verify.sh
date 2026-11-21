#!/bin/bash
# image build-fail — verify. 실행: bash ~/opslab/modules/image/faults/build-fail/verify.sh
source "$(dirname "$(readlink -f "$0")")/../../verify.sh"
verify_main "image build-fail"
