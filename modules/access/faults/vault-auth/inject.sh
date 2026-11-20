#!/bin/bash
# access-2 vault-auth — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: Vault 의 Kubernetes Auth 역할(①)·설정(②), ClusterRoleBinding vault-server-binding(③)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # Auth 역할이 허용하는 네임스페이스 오타(app → apps) — 앱 파드의 로그인 요청이 거절된다
     vt write auth/kubernetes/role/opslab-app bound_service_account_names=opslab-app bound_service_account_namespaces=apps \
       policies=opslab-app ttl=1h >/dev/null ;;
  2) # Vault 가 토큰을 검사하러 가는 쿠버네티스 API 주소 오류(포트 8443) — 로그인 확인 자체를 못 한다
     vt write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc:8443 >/dev/null ;;
  3) # Vault 서비스 계정의 "토큰 검토" 권한(system:auth-delegator) 바인딩 삭제 — 원복용으로 저장
     save crb "$(kubectl get clusterrolebinding vault-server-binding -o json | jq -c 'del(.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields)')"
     kubectl delete clusterrolebinding vault-server-binding >/dev/null ;;
esac
sleep 5; app_restart   # 새로 뜨는 파드의 Vault Agent 가 로그인하면서 증상이 드러난다
record $V
