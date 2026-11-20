#!/bin/bash
# cluster 모듈 장애 스크립트 공통 함수: 공통 함수 + EKS 함수 + 노드에서 명령 실행(Session Manager Run Command)
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
source "$D/node.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
NS=$APP_NS; DEP=opslab-app
kubectl -n "$NS" get deploy "$DEP" >/dev/null 2>&1 || { echo "샘플 앱(deploy/$DEP)이 없습니다. 1단계 구축(모듈 주변 구성 extras/setup.sh)을 먼저 끝내세요."; exit 3; }
# 영향 범위: 노드 한 대(PostgreSQL 이 없는 노드)의 서비스·디스크, app 네임스페이스(course=opslab)의 리소스,
#            노드 역할 접근 항목(cluster-3 ①). kube-system·강사/FIS 접근 항목·계정 IAM 은 바꾸지 않는다.
set -e
# 장애를 넣을 노드: PostgreSQL(디스크가 한 AZ 에 묶인 파드)이 없는 노드 — DB 가 함께 멈춰 원인이 섞이지 않게 한다
target_node() {
  local pg; pg=$(kubectl -n "$NS" get pod postgres-0 -o jsonpath='{.spec.nodeName}' 2>/dev/null)
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -vx "${pg:-none}" | head -1
}
