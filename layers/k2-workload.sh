#!/bin/bash
# K2 층(워크로드 = workload 모듈 완료 상태) — 쿠버네티스 리소스만 있는 층. start.sh 가 실행한다. 다시 실행해도 안전하다.
#   metrics-server(관리형 애드온) → app 네임스페이스 → PostgreSQL·Redis(opslab-data) → 샘플 앱(opslab-app)
# workload 모듈 1단계 구축 따라하기와 같은 명령이다(modules/workload/full.sh 도 이 파일을 실행한다).
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../common/eks.sh"
kube_login
# metrics-server: EKS 관리형 애드온(AWS 가 이미지·버전을 관리)
aws eks describe-addon --cluster-name "$CLUSTER" --addon-name metrics-server >/dev/null 2>&1 \
  || aws eks create-addon --cluster-name "$CLUSTER" --addon-name metrics-server --resolve-conflicts OVERWRITE \
       --tags Course=opslab,Module=workload,Owner="$SID" >/dev/null \
  || { echo "❌ metrics-server 애드온 생성 실패"; exit 1; }
aws eks wait addon-active --cluster-name "$CLUSTER" --addon-name metrics-server || { echo "❌ metrics-server 애드온이 ACTIVE 가 되지 않음"; exit 1; }
echo "  metrics-server"
kubectl create namespace "$APP_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$APP_NS" course=opslab --overwrite >/dev/null
helm upgrade --install opslab-data "$EKS_ROOT/charts/opslab-data" -n "$APP_NS" --wait --timeout 10m \
  --set postgres.image="$(img postgres)" --set redis.image="$(img redis)" >/dev/null \
  || { echo "❌ PostgreSQL·Redis 설치 실패"; exit 1; }
echo "  PostgreSQL·Redis"
helm upgrade --install opslab-app "$EKS_ROOT/charts/opslab-app" -n "$APP_NS" --wait --timeout 10m \
  --set image.repository="$(img_repo app)" --set image.tag="$(img_tag app)" \
  --set waitForDb.image="$(img busybox)" >/dev/null \
  || { echo "❌ 샘플 앱 설치 실패"; exit 1; }
echo "  샘플 앱 opslab-app (파드 2개)"
