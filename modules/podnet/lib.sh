#!/bin/bash
# podnet 모듈 장애 스크립트 공통 함수: 공통 함수 + EKS 함수 + 샘플 앱(app/opslab-app)·Ingress 찾기
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
NS=$APP_NS; DEP=opslab-app
kubectl -n "$NS" get deploy "$DEP" >/dev/null 2>&1 || { echo "샘플 앱(deploy/$DEP)이 없습니다. 환경 층 배포(start.sh podnet)를 먼저 끝내세요."; exit 3; }
kubectl -n "$NS" get ingress "$DEP" >/dev/null 2>&1 || { echo "Ingress($DEP)가 없습니다. 1단계 구축 2를 먼저 끝내세요."; exit 3; }
# 영향 범위: app 네임스페이스(course=opslab)의 리소스, kube-system 의 관리형 애드온(CoreDNS·VPC CNI) 설정,
#           실습 태그(Course=opslab·Owner=<학번>)가 붙은 ENI·보안 그룹 규칙만 바꾼다. 계정 IAM·접근 항목은 바꾸지 않는다.
set -e   # 주입 명령 하나라도 실패하면 즉시 멈춘다(common/inject.sh 가 원복하고 실패를 알린다)
K3="$EKS_ROOT/layers/k3-ingress"
ingress_restore() {   # apply 만 쓴다 — replace --force 는 Ingress 를 지웠다 다시 만들어 ALB 주소가 바뀐다
  sed "s/__SID__/$SID/g" "$K3/ingress.yaml" | kubectl apply -f - >/dev/null && echo "  Ingress 를 기준 상태로 복원"; }
app_restore() {   # 샘플 앱을 차트 기준으로(덧붙인 필드 제거)
  helm -n "$NS" upgrade opslab-app "$EKS_ROOT/charts/opslab-app" --reuse-values --force --wait --timeout 5m >/dev/null \
    && echo "  앱(Deployment·Service)을 차트 기준으로 복원" || { echo "  ⚠️ helm 복원 실패"; return 1; }
}
wait_alb_healthy() {  # ALB 로 /health 가 200 이 될 때까지(최대 5분)
  local h; for i in $(seq 1 30); do
    h=$(kubectl -n "$NS" get ingress "$DEP" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    [ -n "$h" ] && [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$h/health")" = 200 ] && return 0; sleep 10
  done; return 1
}
