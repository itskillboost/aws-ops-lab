#!/bin/bash
# Headlamp(웹 대시보드) 접속 준비 — 매일 아침, 그리고 내 PC 의 네트워크가 바뀌면 다시 실행한다.
#   bash ~/opslab/common/headlamp.sh
# ① 내 PC 공인 IP 를 묻고 ② 그 IP 만 들어올 수 있게 접속 허용 범위를 고치고 ③ 8시간짜리 로그인 토큰을 발급해 ④ 주소와 토큰을 보여 준다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
source "$(dirname "$(readlink -f "$0")")/eks.sh"
kube_login
kubectl -n headlamp get svc headlamp >/dev/null 2>&1 || { echo "❌ Headlamp 가 아직 설치되지 않았습니다(클러스터 층 배포가 끝났는지 start.sh status 로 확인)."; exit 1; }
echo "① 내 PC 의 브라우저에서 https://checkip.amazonaws.com 을 열고, 보이는 숫자(예: 211.45.67.89)를 붙여 넣으세요."
echo "   (CloudShell 의 IP 는 내 PC 의 IP 가 아니므로 직접 확인해야 합니다)"
IP=${1:-}; [ -z "$IP" ] && read -r -p "   내 PC 공인 IP: " IP
IP=$(tr -d ' \r' <<<"$IP")
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "❌ IP 형식이 아닙니다: '$IP'"; exit 1; }
kubectl -n headlamp patch svc headlamp --type merge -p "{\"spec\":{\"loadBalancerSourceRanges\":[\"$IP/32\"]}}" >/dev/null
grep -q '^export HEADLAMP_SOURCE=' ~/opslab-env.sh 2>/dev/null && sed -i "s#^export HEADLAMP_SOURCE=.*#export HEADLAMP_SOURCE=$IP/32#" ~/opslab-env.sh || echo "export HEADLAMP_SOURCE=$IP/32" >> ~/opslab-env.sh
echo "② 접속 허용: $IP/32 만"
TOKEN=$(kubectl -n headlamp create token headlamp-admin --duration=8h)
echo "③ 로그인 토큰 발급(8시간 유효)"
for i in $(seq 1 30); do
  H=$(kubectl -n headlamp get svc headlamp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  [ -n "$H" ] && break; sleep 5
done
[ -n "$H" ] || { echo "❌ 로드밸런서 주소가 아직 없습니다. 2~3분 뒤 다시 실행하세요."; exit 1; }
echo "④ 접속 주소: http://$H"
echo "   (처음 만든 날은 주소가 열리기까지 2~3분 걸립니다. 'This site can't be reached' 면 잠시 뒤 새로 고침)"
echo
echo "로그인 토큰 — 아래 한 줄 전체를 Headlamp 로그인 화면의 ID token 칸에 붙여 넣으세요:"
echo "$TOKEN"
echo
echo "⚠️ 토큰은 내 클러스터의 관리자 열쇠입니다. 화면 공유·캡처·메신저 전송 금지. 유출이 의심되면 이 스크립트를 다시 실행하세요."
