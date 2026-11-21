#!/bin/bash
# access-5 token — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: Vault Kubernetes Auth 설정과 vault 네임스페이스의 토큰 Secret(①), Vault Auth 역할 opslab-app(②)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2)
case $V in
  1) # 예전에 누군가 "옛 방식 토큰(Secret)"을 Vault 의 토큰 검토용으로 넣어 두었는데, 정리 작업으로 그 Secret 이 지워졌다
     #   → 그 토큰은 즉시 무효가 되고, Vault 는 앱 파드의 토큰을 검사하지 못한다
     kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Secret
metadata: { name: vault-reviewer-token, namespace: vault, annotations: { kubernetes.io/service-account.name: vault } }
type: kubernetes.io/service-account-token
YAML
     for i in $(seq 1 20); do J=$(kubectl -n vault get secret vault-reviewer-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d); [ -n "$J" ] && break; sleep 2; done
     vt write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc:443 token_reviewer_jwt="$J" >/dev/null
     kubectl -n vault delete secret vault-reviewer-token >/dev/null ;;
  2) # "audience 를 지정하라"는 Vault 경고를 보고 역할에 audience=vault 를 넣었다 — 그런데 파드 토큰의 대상(aud)은 vault 가 아니다
     vt write auth/kubernetes/role/opslab-app bound_service_account_names=opslab-app bound_service_account_namespaces="$NS" \
       policies=opslab-app ttl=1h audience=vault >/dev/null ;;
esac
sleep 5; app_restart
record $V
