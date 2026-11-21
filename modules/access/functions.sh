#!/bin/bash
# access 모듈(권한과 시크릿) 함수 — K4 층(layers/k4-access.sh)과 장애 스크립트(lib.sh)가 함께 쓴다.
# 미리 common/eks.sh 를 source 해 두어야 한다(SID·CLUSTER·APP_NS·EKS_ROOT·img).
ACCT=$(aws sts get-caller-identity --query Account --output text)
K4="$EKS_ROOT/layers/k4-access"
APP_ROLE=$SID-access-app-role            # 앱(app/opslab-app)이 빌리는 IAM 역할
UNSEAL_ROLE=$SID-access-unsealer-role    # 봉인 해제 CronJob(vault/vault-unsealer)이 빌리는 IAM 역할
DEV_ROLE=$SID-access-dev-role            # RBAC 실습: 개발자(dev) 로 클러스터에 들어오는 IAM 역할
INIT_SECRET=$SID-access-vault-init       # Vault 봉인 해제 열쇠·루트 토큰(Secrets Manager)
BOUNDARY=arn:aws:iam::$ACCT:policy/opslab-student-boundary
ATAGS="Key=Course,Value=opslab Key=Module,Value=access Key=Owner,Value=$SID"

issuer() { aws eks describe-cluster --name "$CLUSTER" --query cluster.identity.oidc.issuer --output text | sed 's#^https://##'; }

irsa_trust() {  # $1=네임스페이스 $2=서비스 계정 → 신뢰 정책 JSON(이 서비스 계정만 역할을 빌릴 수 있다). 따라하기와 같은 틀(irsa-trust.json)
  sed -e "s/__ACCT__/$ACCT/g" -e "s#__ISSUER__#$(issuer)#g" -e "s/__NS__/$1/g" -e "s/__SA__/$2/g" "$EKS_ROOT/modules/access/irsa-trust.json"
}

irsa_role() {  # $1=역할 $2=네임스페이스 $3=서비스 계정 [$4=인라인 정책 파일] — 있으면 신뢰 정책만 맞춘다
  irsa_trust "$2" "$3" > /tmp/trust-$1.json
  if aws iam get-role --role-name "$1" >/dev/null 2>&1; then
    aws iam update-assume-role-policy --role-name "$1" --policy-document "file:///tmp/trust-$1.json" || return 1
  else
    aws iam create-role --role-name "$1" --assume-role-policy-document "file:///tmp/trust-$1.json" \
      --permissions-boundary "$BOUNDARY" --tags $ATAGS >/dev/null || { echo "❌ IAM 역할 $1 생성 실패"; return 1; }
  fi
  if [ -n "${4:-}" ]; then
    sed -e "s/__ACCT__/$ACCT/g" -e "s/__SID__/$SID/g" "$4" > "/tmp/pol-$1.json"
    aws iam put-role-policy --role-name "$1" --policy-name inline --policy-document "file:///tmp/pol-$1.json" || return 1
  fi
}

vst() { kubectl -n vault exec vault-0 -c vault -- vault status -format=json 2>/dev/null; }   # 봉인돼도(종료 코드 2) JSON 은 나온다
root_token() { aws secretsmanager get-secret-value --secret-id "$INIT_SECRET" --query SecretString --output text | jq -r .root_token; }
vt() { kubectl -n vault exec -i vault-0 -c vault -- env VAULT_TOKEN="$VT" vault "$@"; }   # 루트 토큰으로 vault 명령

vault_init_unseal() {  # 처음이면 초기화(열쇠 1개) → 열쇠를 Secrets Manager 에 보관 → 봉인 해제
  local s j k
  for i in $(seq 1 30); do s=$(vst); [ -n "$s" ] && break; sleep 5; done
  [ -n "$s" ] || { echo "❌ Vault 상태를 읽지 못했습니다 — kubectl -n vault get pod vault-0"; return 1; }
  if [ "$(jq -r .initialized <<<"$s")" != true ]; then
    j=$(kubectl -n vault exec vault-0 -c vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json) || { echo "❌ Vault 초기화 실패"; return 1; }
    j=$(jq -c '{unseal_key: .unseal_keys_b64[0], root_token: .root_token}' <<<"$j")
    if aws secretsmanager describe-secret --secret-id "$INIT_SECRET" >/dev/null 2>&1; then
      aws secretsmanager put-secret-value --secret-id "$INIT_SECRET" --secret-string "$j" >/dev/null || return 1
    else
      aws secretsmanager create-secret --name "$INIT_SECRET" --secret-string "$j" --tags $ATAGS >/dev/null || return 1
    fi
  fi
  if [ "$(jq -r .sealed <<<"$(vst)")" = true ]; then
    k=$(aws secretsmanager get-secret-value --secret-id "$INIT_SECRET" --query SecretString --output text | jq -r .unseal_key)
    kubectl -n vault exec vault-0 -c vault -- vault operator unseal "$k" >/dev/null || { echo "❌ 봉인 해제 실패"; return 1; }
  fi
  for i in $(seq 1 24); do [ "$(jq -r .sealed <<<"$(vst)")" = false ] && return 0; sleep 5; done
  echo "❌ Vault 가 봉인 상태입니다 — bash ~/opslab/common/vault-unseal.sh"; return 1
}

vault_configure() {  # KV v2 비밀 → 정책 → Kubernetes Auth(설정·역할). 다시 실행하면 기준 상태로 돌아간다
  VT=$(root_token); local p
  p=$(kubectl -n "$APP_NS" get secret opslab-db -o jsonpath='{.data.password}' | base64 -d)
  vt secrets list -format=json | jq -e '."secret/"' >/dev/null || vt secrets enable -path=secret kv-v2 >/dev/null || return 1
  vt kv put secret/opslab/db user=app password="$p" >/dev/null || return 1
  vt policy write opslab-app - >/dev/null <<'HCL' || return 1
path "secret/data/opslab/db" { capabilities = ["read"] }
HCL
  vt auth list -format=json | jq -e '."kubernetes/"' >/dev/null || vt auth enable kubernetes >/dev/null || return 1
  vt write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc:443 >/dev/null || return 1
  vt write auth/kubernetes/role/opslab-app bound_service_account_names=opslab-app bound_service_account_namespaces="$APP_NS" \
    policies=opslab-app ttl=1h audience="" >/dev/null 2>&1 || return 1   # audience 비움: 쓰기는 덮어쓰기가 아니라 고친 항목만 바뀐다
}

app_to_vault() {  # 샘플 앱: DB 비밀번호는 Vault Agent 가 /etc/app/db-cred.env 로, AWS 신원은 IRSA 로
  helm -n "$APP_NS" upgrade opslab-app "$EKS_ROOT/charts/opslab-app" --reset-then-reuse-values --wait --timeout 6m \
    --set db.source=vault \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::$ACCT:role/$APP_ROLE" >/dev/null \
    || { echo "❌ 샘플 앱 전환 실패 — kubectl -n $APP_NS get pods; kubectl -n $APP_NS describe pod -l app.kubernetes.io/name=opslab-app"; return 1; }
}

dev_iam_role() {  # 개발자 역할: 같은 계정의 IAM 사용자가 빌릴 수 있고, 클러스터에는 쿠버네티스 그룹 opslab-dev 로 들어온다
  if ! aws iam get-role --role-name "$DEV_ROLE" >/dev/null 2>&1; then
    printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::%s:root"},"Action":"sts:AssumeRole"}]}' "$ACCT" > /tmp/dev-trust.json
    aws iam create-role --role-name "$DEV_ROLE" --assume-role-policy-document file:///tmp/dev-trust.json \
      --permissions-boundary "$BOUNDARY" --tags $ATAGS >/dev/null || { echo "❌ IAM 역할 $DEV_ROLE 생성 실패"; return 1; }
  fi
  aws iam put-role-policy --role-name "$DEV_ROLE" --policy-name inline \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"eks:DescribeCluster","Resource":"*"}]}' || return 1
  local arn=arn:aws:iam::$ACCT:role/$DEV_ROLE
  if aws eks describe-access-entry --cluster-name "$CLUSTER" --principal-arn "$arn" >/dev/null 2>&1; then
    aws eks update-access-entry --cluster-name "$CLUSTER" --principal-arn "$arn" --kubernetes-groups opslab-dev >/dev/null || return 1
  else
    for i in $(seq 1 12); do   # 막 만든 IAM 역할은 퍼지는 데 몇 초 걸린다("invalid principal")
      aws eks create-access-entry --cluster-name "$CLUSTER" --principal-arn "$arn" --kubernetes-groups opslab-dev \
        --tags Course=opslab,Module=access,Owner="$SID" >/dev/null 2>&1 && break
      [ "$i" -eq 12 ] && { echo "❌ 접근 항목 생성 실패"; return 1; }; sleep 10
    done
  fi
}

dev_kubectl() {  # dev 역할로 kubectl 실행(별도 kubeconfig) — 예: dev_kubectl -n app get pods
  [ -f /tmp/kube-dev ] || aws eks update-kubeconfig --name "$CLUSTER" --role-arn "arn:aws:iam::$ACCT:role/$DEV_ROLE" --kubeconfig /tmp/kube-dev >/dev/null
  kubectl --kubeconfig /tmp/kube-dev "$@"
}
