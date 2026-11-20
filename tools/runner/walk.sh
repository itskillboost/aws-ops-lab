#!/bin/bash
# 따라하기 명령 그대로 실행 시험 (작성자용) — 모듈 페이지의 따라하기 명령을 페이지 순서대로 실행해 막히는 단계를 찾는다.
#   SID=s00 bash tools/runner/walk.sh workload
# 명령 목록은 modules/<모듈>/walk.steps (한 줄에 명령 하나, 페이지와 같은 순서. # 은 주석, 줄 끝 \ 은 다음 줄과 이어짐).
# 대화형 입력: headlamp.sh 는 이 러너의 공인 IP 를 인자로 넣고, less 는 head 로 바꿔 실행한다.
set -uo pipefail
: "${SID:?}"; MOD=${1:?모듈}; ROOT=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
F="$ROOT/modules/$MOD/walk.steps"; [ -f "$F" ] || { echo "없음: $F"; exit 1; }
MYIP=$(curl -s https://checkip.amazonaws.com); R=0; N=0
step() { N=$((N+1)); echo; echo "▶▶ [$N] $1"; eval "$1"; local rc=$?; echo "◀◀ rc=$rc"; [ $rc -ne 0 ] && { R=$((R+1)); echo "!!! 실패: $1"; }; }
buf=""
while IFS= read -r line || [ -n "$line" ]; do
  [[ -z "$buf" && ( "$line" =~ ^[[:space:]]*# || -z "${line// }" ) ]] && continue
  if [[ "$line" == *\\ ]]; then buf+="${line%\\} "; continue; fi   # 줄 끝 \ 은 공백으로 이어 붙인다(셸과 같게)
  cmd="$buf$line"; buf=""
  cmd=${cmd//common\/headlamp.sh/common\/headlamp.sh $MYIP}; cmd=${cmd//| less/| head -20}
  [[ "$cmd" == *headlamp.sh* ]] && cmd+=" | grep -v '^eyJ'"   # 로그에 토큰을 남기지 않는다
  step "$cmd"
done < "$F"
echo; echo "=== 따라하기 $N 단계 중 실패 $R"
exit $R
