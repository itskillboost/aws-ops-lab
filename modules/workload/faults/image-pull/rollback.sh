#!/bin/bash
# workload-5 image-pull — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
aws iam attach-role-policy --role-name "$SID-cluster-node-role" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly && echo "  노드 역할 ECR 읽기 정책 확인"
helm_restore
