# access 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="env irsa vault auth app rbac load"
_acc() { [ -n "${ACCT:-}" ] || source "$EKS_ROOT/modules/access/functions.sh"; }
stage_env() {       # 사전 조건: K3 층(클러스터·샘플 앱·DB·ALB)
  kube_login && kubectl get ns default >/dev/null 2>&1 && ok "kubectl 접속(kubeconfig)" || { ng "kubectl 로 접속되지 않습니다" "bash ~/opslab/common/start.sh access"; return; }
  [ "$(kubectl -n app get deploy opslab-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 2 ] && ok "샘플 앱 파드 2개 Ready" || ng "샘플 앱이 Ready 가 아닙니다" "bash ~/opslab/common/start.sh access (다시 실행하면 이어서 합니다)"
  local h; h=$(kubectl -n app get ingress opslab-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$h" ] && ok "Ingress(ALB) $h" || ng "Ingress 에 ALB 주소가 없습니다" "bash ~/opslab/common/start.sh access"
}
stage_irsa() {      # 구축 1: 앱 IRSA 역할
  _acc
  aws iam get-role --role-name "$APP_ROLE" --query Role.PermissionsBoundary.PermissionsBoundaryArn --output text 2>/dev/null | grep -q opslab-student-boundary \
    && ok "IAM 역할 $APP_ROLE (권한 경계 포함)" || ng "IAM 역할이 없거나 권한 경계가 없습니다" "구축 1 — aws iam create-role … --permissions-boundary …"
  aws iam get-role --role-name "$APP_ROLE" --query Role.AssumeRolePolicyDocument --output json 2>/dev/null | grep -q "system:serviceaccount:app:opslab-app" \
    && ok "신뢰 정책: app/opslab-app 서비스 계정만 허용" || ng "신뢰 정책의 서비스 계정 조건이 다릅니다" "구축 1 — cat ~/app-trust.json 확인 후 update-assume-role-policy"
}
stage_vault() {     # 구축 2: Vault 설치·초기화·봉인 해제
  _acc
  [ "$(kubectl -n vault get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && ok "Vault 서버 파드 vault-0 Running" || { ng "vault-0 이 Running 이 아닙니다" "구축 2 — helm upgrade --install vault …"; return; }
  [ "$(vst | jq -r .initialized)" = true ] && ok "Vault 초기화됨" || ng "Vault 가 초기화되지 않았습니다" "구축 2 — vault operator init"
  [ "$(vst | jq -r .sealed)" = false ] && ok "Vault 봉인 해제됨" || ng "Vault 가 봉인돼 있습니다" "bash ~/opslab/common/vault-unseal.sh"
  aws secretsmanager describe-secret --secret-id "$INIT_SECRET" >/dev/null 2>&1 && ok "열쇠 보관: Secrets Manager $INIT_SECRET" || ng "열쇠가 Secrets Manager 에 없습니다" "구축 2 — aws secretsmanager create-secret …"
  kubectl -n vault get cronjob vault-unsealer >/dev/null 2>&1 && ok "봉인 해제 CronJob vault-unsealer" || ng "봉인 해제 CronJob 이 없습니다" "구축 2 — unsealer.yaml 적용"
}
stage_auth() {      # 구축 3: 비밀·정책·Kubernetes Auth
  _acc; VT=$(root_token 2>/dev/null)
  vt kv get -format=json secret/opslab/db >/dev/null 2>&1 && ok "비밀 secret/opslab/db" || ng "비밀이 없습니다" "구축 3 — vault kv put secret/opslab/db …"
  vt policy read opslab-app 2>/dev/null | grep -q 'secret/data/opslab/db' && ok "정책 opslab-app (secret/data/opslab/db 읽기)" || ng "정책이 없거나 경로가 다릅니다" "구축 3 — vault policy write opslab-app …"
  vt read -format=json auth/kubernetes/role/opslab-app 2>/dev/null | jq -e '.data.bound_service_account_namespaces|index("app")' >/dev/null \
    && ok "Kubernetes Auth 역할 opslab-app (app/opslab-app)" || ng "Kubernetes Auth 역할이 없거나 조건이 다릅니다" "구축 3 — vault write auth/kubernetes/role/opslab-app …"
}
stage_app() {       # 구축 4: 앱 전환(Vault 주입 + IRSA)
  _acc
  local n; n=$(kubectl -n app get pods -l app.kubernetes.io/name=opslab-app -o jsonpath='{range .items[*]}{.spec.containers[*].name}{"\n"}{end}' 2>/dev/null | grep -c vault-agent)
  [ "$n" -ge 2 ] && ok "앱 파드에 Vault Agent 사이드카 ${n}개" || ng "앱 파드에 사이드카가 없습니다" "구축 4 — helm upgrade opslab-app … --set db.source=vault"
  local h; h=$(kubectl -n app get ingress opslab-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ "$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$h/db")" = 200 ] && ok "ALB 로 /db 200 (Vault 에서 받은 비밀번호로 DB 접속)" || ng "/db 가 200 이 아닙니다" "kubectl -n app logs deploy/opslab-app -c vault-agent"
  curl -s -m 10 "http://$h/aws" | grep -q "$APP_ROLE" && ok "/aws: IRSA 역할 $APP_ROLE" || ng "/aws 가 IRSA 역할이 아닙니다" "구축 4 — 서비스 계정 어노테이션 확인 후 kubectl -n app rollout restart deploy opslab-app"
}
stage_rbac() {      # 구축 5: RBAC dev 역할
  _acc
  kubectl -n app get rolebinding dev >/dev/null 2>&1 && ok "Role·RoleBinding dev (그룹 opslab-dev)" || ng "RoleBinding dev 가 없습니다" "구축 5 — kubectl apply -f ~/opslab/layers/k4-access/rbac-dev.yaml"
  aws eks describe-access-entry --cluster-name "$CLUSTER" --principal-arn "arn:aws:iam::$ACCT:role/$DEV_ROLE" --query 'accessEntry.kubernetesGroups' --output text 2>/dev/null | grep -qw opslab-dev \
    && ok "접근 항목: $DEV_ROLE → 그룹 opslab-dev" || ng "접근 항목이 없거나 그룹이 다릅니다" "구축 5 — aws eks create-access-entry …"
  [ "$(dev_kubectl auth can-i list pods -n app 2>/dev/null)" = yes ] && ok "dev 로 파드 조회 가능" || ng "dev 로 파드를 조회할 수 없습니다" "구축 5 확인 명령 다시"
}
stage_load() {      # 2단계(정상 상태 정의)
  kubectl -n app get deploy opslab-load -o jsonpath='{.spec.template.spec.containers[0].env[0].value}' 2>/dev/null | grep -q elb.amazonaws.com \
    && ok "부하 파드가 ALB 로 요청 중" || ng "부하 파드가 없거나 ALB 로 보내지 않습니다" "2단계 — bash ~/opslab/common/load.sh pod alb"
  [ -f ~/opslab-work/access/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/access/baseline/verify.sh"
}
