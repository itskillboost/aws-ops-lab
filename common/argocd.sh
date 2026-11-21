#!/bin/bash
# Argo CD 접속 준비 — Argo CD 를 설치한 뒤, 그리고 GitOps 를 쓰는 날(gitops·image·heal) 아침마다 실행한다.
#   bash ~/opslab/common/argocd.sh
# ① 화면(UI) 접속 허용 IP 를 내 PC IP 로(headlamp.sh 에서 넣은 값을 그대로 쓴다) ② 화면 주소와 admin 비밀번호를 보여 주고
# ③ CloudShell 의 argocd CLI 를 로그인시킨다(포트 포워딩 — CloudShell 은 내 PC IP 가 아니므로 로드밸런서 대신 클러스터 안으로 바로 붙는다)
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
source "$(dirname "$(readlink -f "$0")")/eks.sh"
kube_login
kubectl -n argocd get svc argocd-server >/dev/null 2>&1 || { echo "❌ Argo CD 가 아직 설치되지 않았습니다(gitops 구축 2 또는 start.sh 로 K5 층 배포)."; exit 1; }
SRC=${HEADLAMP_SOURCE:-}
if [ -z "$SRC" ]; then
  echo "① 내 PC 의 브라우저에서 https://checkip.amazonaws.com 을 열고, 보이는 숫자를 붙여 넣으세요."
  IP=${1:-}; [ -z "$IP" ] && read -r -p "   내 PC 공인 IP: " IP; IP=$(tr -d ' \r' <<<"$IP")
  [[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "❌ IP 형식이 아닙니다: '$IP'"; exit 1; }
  SRC=$IP/32; echo "export HEADLAMP_SOURCE=$SRC" >> ~/opslab-env.sh
fi
kubectl -n argocd patch svc argocd-server --type merge -p "{\"spec\":{\"loadBalancerSourceRanges\":[\"$SRC\"]}}" >/dev/null
echo "① 화면 접속 허용: $SRC 만 (내 PC IP 가 바뀌면 headlamp.sh 를 다시 실행하세요 — Argo CD 도 함께 바뀝니다)"
P=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
for i in $(seq 1 30); do H=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'); [ -n "$H" ] && break; sleep 5; done
echo "② 화면 주소: http://${H:-(아직 없음 — 2~3분 뒤 다시 실행)}   사용자 admin / 비밀번호: $P"
echo "   (처음 만든 날은 주소가 열리기까지 2~3분 걸립니다)"
grep -q '^export ARGOCD_OPTS=' ~/opslab-env.sh 2>/dev/null || echo 'export ARGOCD_OPTS="--port-forward --port-forward-namespace argocd --plaintext"' >> ~/opslab-env.sh
export ARGOCD_OPTS="--port-forward --port-forward-namespace argocd --plaintext"
argocd login --username admin --password "$P" >/dev/null 2>&1 && echo "③ argocd CLI 로그인 완료 — 새 터미널에서는 source ~/opslab-env.sh 후 사용" \
  || echo "❌ argocd CLI 로그인 실패 — kubectl -n argocd get pods 로 argocd-server 가 Ready 인지 확인하세요"
echo "⚠️ admin 비밀번호는 내 Argo CD 의 관리자 열쇠입니다. 화면 공유·캡처·메신저 전송 금지."
