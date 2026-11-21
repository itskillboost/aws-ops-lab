#!/bin/bash
# access-3 inject — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment 의 파드 어노테이션(①), Vault 정책 opslab-app(②), vault/vault-agent-injector 복제본 수(③)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # 주입 템플릿의 비밀 경로 오타(opslab/db → opslab/dv) — Vault 에 없는 비밀을 기다리며 init 에서 멈춘다
     T=$(kubectl -n "$NS" get deploy "$DEP" -o json | jq -r '.spec.template.metadata.annotations["vault.hashicorp.com/agent-inject-template-db-cred.env"]' | sed 's#opslab/db#opslab/dv#')
     kubectl -n "$NS" patch deploy "$DEP" --type merge -p "$(jq -n --arg t "$T" '{spec:{template:{metadata:{annotations:{"vault.hashicorp.com/agent-inject-template-db-cred.env":$t,"vault.hashicorp.com/agent-inject-secret-db-cred.env":"secret/data/opslab/dv"}}}}}')" >/dev/null ;;
  2) # Vault 정책이 다른 경로만 허용 — 로그인은 되지만 비밀을 읽을 권한이 없다(403)
     vt policy write opslab-app - >/dev/null <<'HCL'
path "secret/data/opslab/app" { capabilities = ["read"] }
HCL
     app_restart ;;
  3) # 사이드카 주입기(Agent Injector)를 0개로 — 새 파드에 사이드카가 붙지 않아 비밀번호 파일이 없다
     kubectl -n vault scale deploy vault-agent-injector --replicas=0 >/dev/null
     kubectl -n vault wait --for=delete pod -l app.kubernetes.io/name=vault-agent-injector --timeout=90s >/dev/null 2>&1 || true
     app_restart ;;
esac
record $V
