#!/bin/bash
# K4 층(권한·시크릿 = access 모듈 완료 상태) — start.sh 가 실행한다. 다시 실행해도 안전하다.
#   ① 앱 IRSA 역할 ② Vault(금고) 설치 ③ 초기화·봉인 해제(열쇠는 Secrets Manager 에 보관) ④ 비밀·정책·Kubernetes Auth
#   ⑤ 봉인 해제 CronJob(IRSA) ⑥ 앱을 Vault 주입 + IRSA 로 전환 ⑦ RBAC 실습 역할(dev)과 접근 항목
# access 모듈 1단계 구축 따라하기와 같은 명령이다(modules/access/full.sh 도 이 파일을 실행한다).
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../common/eks.sh"
source "$EKS_ROOT/modules/access/functions.sh"
kube_login

# ① 앱 IRSA 역할 — app/opslab-app 서비스 계정만 빌릴 수 있다
irsa_role "$APP_ROLE" "$APP_NS" opslab-app || exit 1
echo "  IRSA 역할 $APP_ROLE"

# ② Vault — 단일 서버, 파일 저장소(PVC), Agent Injector 포함. 이미지·차트는 미러·고정 차트만 쓴다
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace vault course=opslab --overwrite >/dev/null
helm upgrade --install vault "$EKS_ROOT/vendor/charts/vault" -n vault --timeout 10m \
  --set server.image.repository="$(img_repo vault)" --set server.image.tag="$(img_tag vault)" \
  --set injector.image.repository="$(img_repo vault-k8s)" --set injector.image.tag="$(img_tag vault-k8s)" \
  --set injector.agentImage.repository="$(img_repo vault)" --set injector.agentImage.tag="$(img_tag vault)" \
  --set server.dataStorage.size=1Gi --set server.dataStorage.storageClass=gp3 \
  --set server.resources.requests.cpu=50m --set server.resources.requests.memory=128Mi \
  --set injector.resources.requests.cpu=20m --set injector.resources.requests.memory=64Mi >/dev/null \
  || { echo "❌ Vault 설치 실패"; exit 1; }
kubectl -n vault rollout status deploy vault-agent-injector --timeout=5m >/dev/null
for i in $(seq 1 40); do [ "$(kubectl -n vault get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && break; sleep 5; done
echo "  Vault 설치(vault 네임스페이스)"

# ③ 초기화(처음 한 번) → 열쇠·루트 토큰을 Secrets Manager 에 보관 → 봉인 해제
vault_init_unseal || exit 1
echo "  Vault 초기화·봉인 해제 (열쇠: Secrets Manager $INIT_SECRET)"

# ④ KV 비밀·정책·Kubernetes Auth
vault_configure || exit 1
echo "  Vault 비밀 secret/opslab/db · 정책 opslab-app · Kubernetes Auth 역할 opslab-app"

# ⑤ 봉인 해제 CronJob — Vault 파드가 다시 뜨면(드레인·노드 교체) 1분 안에 봉인을 푼다
irsa_role "$UNSEAL_ROLE" vault vault-unsealer "$EKS_ROOT/modules/access/unsealer-policy.json" || exit 1
sed -e "s#__ROLE_ARN__#arn:aws:iam::$ACCT:role/$UNSEAL_ROLE#" -e "s#__SECRET__#$INIT_SECRET#" -e "s#__IMAGE__#$(img app)#" \
  "$K4/unsealer.yaml" | kubectl apply -f - >/dev/null
echo "  봉인 해제 CronJob vault-unsealer (IRSA $UNSEAL_ROLE)"

# ⑥ 앱 전환 — DB 비밀번호는 Vault 에서(사이드카 주입), AWS 신원은 IRSA 로
app_to_vault || exit 1
echo "  샘플 앱: Vault 주입 + IRSA"

# ⑦ RBAC 실습 — dev 역할(Role·RoleBinding)과 dev 용 IAM 역할 → 접근 항목(쿠버네티스 그룹 opslab-dev)
kubectl apply -f "$K4/rbac-dev.yaml" >/dev/null
dev_iam_role || exit 1
echo "  RBAC 실습 역할 dev (IAM $DEV_ROLE → 그룹 opslab-dev)"
