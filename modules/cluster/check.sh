# cluster 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="env cluster nodes logging insights extras load"
source "$EKS_ROOT/modules/cluster/node.sh" 2>/dev/null
stage_env() {       # 사전 조건: L1 네트워크와 모듈 주변 구성(역할·시작 템플릿)
  aws cloudformation describe-stacks --stack-name "$SID-l1" >/dev/null 2>&1 && ok "L1 네트워크 스택" || ng "L1 스택이 없습니다" "bash ~/opslab/common/start.sh cluster"
  aws iam get-role --role-name "$SID-cluster-ctl-role" >/dev/null 2>&1 && ok "클러스터 역할 $SID-cluster-ctl-role" || ng "클러스터 역할이 없습니다" "bash ~/opslab/common/start.sh cluster"
  aws iam get-role --role-name "$SID-cluster-worker-role" >/dev/null 2>&1 && ok "노드 역할 $SID-cluster-worker-role" || ng "노드 역할이 없습니다" "bash ~/opslab/common/start.sh cluster"
}
stage_cluster() {   # 구축 1: 클러스터
  have_cluster && ok "클러스터 $CLUSTER ACTIVE" || { ng "클러스터가 ACTIVE 가 아닙니다" "구축 1 — aws eks create-cluster → aws eks wait cluster-active"; return; }
  [ "$(aws eks describe-cluster --name "$CLUSTER" --query cluster.accessConfig.authenticationMode --output text)" = API ] && ok "인증 모드 API(접근 항목)" || ng "인증 모드가 API 가 아닙니다" "구축 1 — --access-config authenticationMode=API"
  kube_login && kubectl get ns default >/dev/null 2>&1 && ok "kubectl 접속(kubeconfig)" || ng "kubectl 로 접속되지 않습니다" "aws eks update-kubeconfig --name $CLUSTER --alias $SID"
}
stage_nodes() {     # 구축 2: 노드 그룹
  [ "$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)" -ge 2 ] && ok "노드 2대 Ready" || ng "Ready 노드가 2대 미만" "구축 2 — aws eks wait nodegroup-active, kubectl get nodes"
  kubectl get nodes -l opslab/pool=default --no-headers 2>/dev/null | grep -q . && ok "노드 라벨 opslab/pool=default" || ng "노드 라벨이 없습니다" "구축 2 — --labels opslab/pool=default"
  [ "$(aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=tag:Module,Values=cluster Name=instance-state-name,Values=running --query 'length(Reservations[].Instances[])' --output text)" -ge 2 ] \
    && ok "노드 EC2 에 실습 태그(시작 템플릿)" || ng "노드 EC2 에 태그가 없습니다" "구축 2 — --launch-template id=\$WORKER_LAUNCH_TEMPLATE"
}
stage_logging() {   # 구축 3: 컨트롤 플레인 로그
  local t; t=$(aws eks describe-cluster --name "$CLUSTER" --query 'cluster.logging.clusterLogging[?enabled].types[]' --output text)
  for x in api audit authenticator controllerManager scheduler; do grep -qw "$x" <<<"$t" || { ng "컨트롤 플레인 로그 $x 꺼짐" "구축 3 — aws eks update-cluster-config --logging …"; return; }; done
  ok "컨트롤 플레인 로그 5종 켜짐"
}
stage_insights() {  # 구축 4: Container Insights
  [ "$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name amazon-cloudwatch-observability --query addon.status --output text 2>/dev/null)" = ACTIVE ] \
    && ok "Container Insights 애드온 ACTIVE" || ng "Container Insights 애드온이 ACTIVE 가 아닙니다" "구축 4 — aws eks create-addon … amazon-cloudwatch-observability"
}
stage_extras() {    # 구축 5: 주변 구성
  local acct; acct=$(aws sts get-caller-identity --query Account --output text)
  aws eks describe-access-entry --cluster-name "$CLUSTER" --principal-arn "arn:aws:iam::$acct:role/opslab-instructor-readonly" >/dev/null 2>&1 \
    && ok "강사 읽기 전용 접근 항목" || ng "강사 접근 항목이 없습니다" "구축 5 — bash ~/opslab/modules/cluster/extras/setup.sh"
  kubectl -n headlamp get deploy headlamp >/dev/null 2>&1 && ok "Headlamp 설치됨" || ng "Headlamp 없음" "구축 5 — extras/setup.sh"
  [ "$(kubectl -n app get deploy opslab-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 2 ] && ok "샘플 앱 파드 2개 Ready" || ng "샘플 앱이 Ready 가 아닙니다" "구축 5 — extras/setup.sh (다시 실행해도 안전)"
}
stage_load() {      # 2단계(정상 상태 정의)
  kubectl -n app get deploy opslab-load >/dev/null 2>&1 && ok "부하 파드 실행 중" || ng "부하 파드 없음" "2단계 — bash ~/opslab/common/load.sh pod"
  [ -f ~/opslab-work/cluster/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/cluster/baseline/verify.sh"
}
