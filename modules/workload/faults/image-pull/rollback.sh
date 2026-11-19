#!/bin/bash
# workload-5 image-pull — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
R=$(load repo); [ -n "$R" ] && [ "$R" != None ] && aws ecr delete-repository-policy --repository-name "$R" >/dev/null 2>&1 && echo "  ECR 저장소 정책 삭제: $R"
helm_restore
