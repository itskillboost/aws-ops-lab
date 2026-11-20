#!/bin/bash
# access 모듈 장애 스크립트 공통: 공통 함수 + EKS 함수 + access 함수(functions.sh) + 샘플 앱·Vault 찾기
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
source "$D/functions.sh"
NS=$APP_NS; DEP=opslab-app
kubectl -n "$NS" get deploy "$DEP" >/dev/null 2>&1 || { echo "샘플 앱(deploy/$DEP)이 없습니다. 환경 층 배포(start.sh access)를 먼저 끝내세요."; exit 3; }
kubectl -n vault get pod vault-0 >/dev/null 2>&1 || { echo "Vault(vault/vault-0)가 없습니다. 1단계 구축 2를 먼저 끝내세요."; exit 3; }
# 영향 범위: app·vault 네임스페이스(course=opslab)의 리소스, Vault 안의 설정(정책·Auth), 실습 태그가 붙은 IAM 역할(<학번>-access-*)의
#           신뢰 정책·접근 항목, 이 클러스터의 OIDC 공급자만 바꾼다. 강사 읽기 전용·FIS 접근 항목과 계정 전체 IAM 은 바꾸지 않는다.
set -e   # 주입 명령 하나라도 실패하면 즉시 멈춘다(common/inject.sh 가 원복하고 실패를 알린다)
VT=$(root_token)
app_restart() { kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null; }   # 새 파드가 뜨면서 증상이 드러난다
app_wait() { kubectl -n "$NS" rollout status deploy "$DEP" --timeout="${1:-5m}" >/dev/null; }
app_restore() {   # 샘플 앱을 차트 기준(Vault 주입 + IRSA)으로 — 덧붙이거나 바꾼 필드도 되돌린다
  helm -n "$NS" upgrade opslab-app "$EKS_ROOT/charts/opslab-app" --reset-then-reuse-values --force --wait --timeout 6m \
    --set db.source=vault --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::$ACCT:role/$APP_ROLE" >/dev/null \
    && echo "  앱(Deployment·서비스 계정)을 차트 기준으로 복원" || { echo "  ⚠️ helm 복원 실패"; return 1; }
}
