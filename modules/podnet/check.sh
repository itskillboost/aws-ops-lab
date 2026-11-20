# podnet 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="env irsa lbc ingress netpol load"
stage_env() {       # 사전 조건: K2 층(클러스터·샘플 앱·DB)
  kube_login && kubectl get ns default >/dev/null 2>&1 && ok "kubectl 접속(kubeconfig)" || { ng "kubectl 로 접속되지 않습니다" "bash ~/opslab/common/start.sh podnet"; return; }
  [ "$(kubectl -n app get deploy opslab-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 2 ] && ok "샘플 앱 파드 2개 Ready" || ng "샘플 앱이 Ready 가 아닙니다" "bash ~/opslab/common/start.sh podnet (다시 실행하면 이어서 합니다)"
  aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | grep -q "$(aws eks describe-cluster --name "$CLUSTER" --query cluster.identity.oidc.issuer --output text | awk -F/ '{print $NF}')" \
    && ok "OIDC 공급자(IRSA 신원 확인 창구)" || ng "OIDC 공급자가 없습니다" "강사 호출(K1 층 문제)"
}
stage_irsa() {      # 구축 1: Load Balancer Controller 용 IRSA 역할
  local acct; acct=$(aws sts get-caller-identity --query Account --output text)
  aws iam get-policy --policy-arn "arn:aws:iam::$acct:policy/$SID-podnet-lbc-policy" >/dev/null 2>&1 && ok "IAM 정책 $SID-podnet-lbc-policy" || ng "IAM 정책이 없습니다" "구축 1 — aws iam create-policy …"
  aws iam get-role --role-name "$SID-podnet-lbc-role" --query Role.PermissionsBoundary.PermissionsBoundaryArn --output text 2>/dev/null | grep -q opslab-student-boundary \
    && ok "IAM 역할 $SID-podnet-lbc-role (권한 경계 포함)" || ng "IAM 역할이 없거나 권한 경계가 없습니다" "구축 1 — aws iam create-role … --permissions-boundary …"
  aws iam list-attached-role-policies --role-name "$SID-podnet-lbc-role" --query 'AttachedPolicies[].PolicyName' --output text 2>/dev/null | grep -q "$SID-podnet-lbc-policy" \
    && ok "역할에 정책 연결됨" || ng "역할에 정책이 연결되지 않았습니다" "구축 1 — aws iam attach-role-policy …"
}
stage_lbc() {       # 구축 2: Load Balancer Controller
  [ "$(kubectl -n kube-system get deploy aws-load-balancer-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" -ge 1 ] 2>/dev/null \
    && ok "Load Balancer Controller Ready" || ng "Load Balancer Controller 가 Ready 가 아닙니다" "구축 2 — helm upgrade --install aws-load-balancer-controller …, kubectl -n kube-system logs deploy/aws-load-balancer-controller"
  kubectl -n kube-system get sa aws-load-balancer-controller -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null | grep -q "$SID-podnet-lbc-role" \
    && ok "서비스 계정에 IRSA 역할 어노테이션" || ng "서비스 계정에 역할 어노테이션이 없습니다" "구축 2 — --set serviceAccount.annotations…"
  kubectl get mutatingwebhookconfiguration aws-load-balancer-webhook -o json 2>/dev/null | jq -e '[.webhooks[].name] | index("mservice.elbv2.k8s.aws") | not' >/dev/null \
    && ok "LoadBalancer Service 가로채기 꺼짐(Headlamp NLB 보호)" || ng "Service 가로채기가 켜져 있습니다" "구축 2 — --set enableServiceMutatorWebhook=false"
}
stage_ingress() {   # 구축 3: Ingress(ALB)
  local h; h=$(kubectl -n app get ingress opslab-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$h" ] && ok "Ingress 에 ALB 주소: $h" || { ng "Ingress 에 ALB 주소가 없습니다" "구축 3 — kubectl -n app describe ingress opslab-app 의 Events"; return; }
  [ "$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$h/health")" = 200 ] && ok "ALB 로 /health 200" || ng "ALB 로 /health 가 200 이 아닙니다" "ALB 를 만드는 데 2~3분 걸립니다 — 잠시 뒤 다시"
}
stage_netpol() {    # 구축 4: VPC CNI 네트워크 정책 + 기본 NetworkPolicy
  aws eks describe-addon --cluster-name "$CLUSTER" --addon-name vpc-cni --query addon.configurationValues --output text 2>/dev/null | grep -q '"enableNetworkPolicy" *: *"true"' \
    && ok "VPC CNI 네트워크 정책 기능 켜짐" || ng "VPC CNI 네트워크 정책 기능이 꺼져 있습니다" "구축 4 — aws eks update-addon … enableNetworkPolicy"
  kubectl -n app get networkpolicy db-allow-app >/dev/null 2>&1 && ok "NetworkPolicy db-allow-app" || ng "NetworkPolicy 가 없습니다" "구축 4 — kubectl apply -f ~/opslab/layers/k3-ingress/netpol.yaml"
}
stage_load() {      # 2단계(정상 상태 정의)
  kubectl -n app get deploy opslab-load -o jsonpath='{.spec.template.spec.containers[0].env[0].value}' 2>/dev/null | grep -q elb.amazonaws.com \
    && ok "부하 파드가 ALB 로 요청 중" || ng "부하 파드가 없거나 ALB 로 보내지 않습니다" "2단계 — bash ~/opslab/common/load.sh pod alb"
  [ -f ~/opslab-work/podnet/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/podnet/baseline/verify.sh"
}
