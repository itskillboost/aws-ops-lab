#!/bin/bash
# access-2 vault-auth — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
if ! kubectl get clusterrolebinding vault-server-binding >/dev/null 2>&1; then
  C=$(load crb)
  if [ -n "$C" ] && [ "$C" != None ]; then kubectl apply -f - <<<"$C" >/dev/null
  else kubectl create clusterrolebinding vault-server-binding --clusterrole=system:auth-delegator --serviceaccount=vault:vault >/dev/null; fi
  echo "  ClusterRoleBinding vault-server-binding 복원"; aws ssm delete-parameter --name "$STATE/crb" >/dev/null 2>&1
fi
vault_configure && echo "  Vault Kubernetes Auth 설정·역할 복원"
app_restart; app_wait && echo "  앱 배포 완료"
