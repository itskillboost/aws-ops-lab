#!/bin/bash
# workload 모듈 장애 스크립트 공통 함수: 공통 함수 + EKS 함수 + 샘플 앱(app/opslab-app) 찾기
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
NS=$APP_NS; DEP=opslab-app
kubectl -n "$NS" get deploy "$DEP" >/dev/null 2>&1 || { echo "샘플 앱(deploy/$DEP)이 없습니다. 1단계 구축을 먼저 끝내세요."; exit 3; }
# 영향 범위: app 네임스페이스(course=opslab)의 리소스와, workload-1 ③ 의 노드 taint(opslab/ 접두어)만 바꾼다

patch() { kubectl -n "$NS" patch deploy "$DEP" "$@" >/dev/null; }   # 앱 Deployment 수정
# 원복: 차트 기준 상태로 되돌린다. --force 는 살아 있는 객체를 차트 매니페스트로 통째로 교체해,
#       kubectl 로 덧붙인 필드(nodeSelector·command 등)까지 지운다. 수강생이 helm --set 으로 고친 값은 유지된다.
helm_restore() {
  helm -n "$NS" upgrade opslab-app "$EKS_ROOT/charts/opslab-app" --reuse-values --force --wait --timeout 5m >/dev/null \
    && echo "  앱 Deployment 를 차트 기준으로 복원" || { echo "  ⚠️ helm 복원 실패"; return 1; }
}
