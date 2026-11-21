#!/bin/bash
# access-4 rbac — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl apply -f "$K4/rbac-dev.yaml" >/dev/null && echo "  Role·RoleBinding dev 복원"
aws eks update-access-entry --cluster-name "$CLUSTER" --principal-arn "arn:aws:iam::$ACCT:role/$DEV_ROLE" --kubernetes-groups opslab-dev >/dev/null && echo "  접근 항목 그룹 opslab-dev 복원"
sleep 5
