#!/bin/bash
# 장애 주입 도구 (수강생용) — CloudShell에서 내 권한으로 실행한다.
#   bash ~/opslab/common/inject.sh cmp-1            Lab cmp-1 장애 주입 (가설 수립을 끝낸 뒤)
#   bash ~/opslab/common/inject.sh done cmp-1       해결 기록 (verify.sh 통과 후)
#   bash ~/opslab/common/inject.sh rollback cmp-1   원복 (주입 후 40분 안에 해결하지 못했을 때)
#   bash ~/opslab/common/inject.sh retry cmp-1      재도전: 원복한 Lab 에 같은 변형을 다시 주입 (해답을 보며 직접 해결)
#   bash ~/opslab/common/inject.sh status         내 Lab별 주입·해결·원복 기록 보기
#
# 장애 내용은 modules/<모듈ID>/faults/<장애명>/inject.sh 에 공개되어 있다. 무작위 변형 하나를 주입하고,
# 기록(시각·변형·원복 정보)은 내 계정 SSM Parameter Store /opslab/injections/<Lab> 에 남긴다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}" SID
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
P=/opslab/injections
now() { TZ=Asia/Seoul date '+%Y-%m-%dT%H:%M:%S%z'; }
usage() { sed -n '3,7p' "$0" | sed 's/^#//'; exit 1; }

case "${1:-}" in
  [a-z]*-[0-9]*) ACTION=inject; LAB=$1 ;;
  done|rollback|retry) ACTION=$1; LAB=${2:-}; [ -z "$LAB" ] && usage ;;
  status) ACTION=status; LAB="" ;;
  *) usage ;;
esac

if [ "$ACTION" = status ]; then
  echo "✅ $SID 주입 기록"
  aws ssm get-parameters-by-path --path "$P" --query 'Parameters[].Value' --output json 2>/dev/null \
    | jq -r '.[] | fromjson? | objects | select(.lab) | "  Lab \(.lab)  \(.state|.+"           "|.[0:11]) 주입 \(.injected_at // "-")  해결 \(.resolved_at // "-")  원복 \(.rolled_back_at // "-")\(if .retry then "  (재도전)" else "" end)"' | sort
  exit 0
fi

MOD=${LAB%%-*}; MY="$ROOT/modules/$MOD/module.yaml"
ROW=$(grep -E "^ *- *$LAB *\|" "$MY" 2>/dev/null) || { echo "❌ Lab ID를 찾지 못했습니다: $LAB (modules/<모듈ID>/module.yaml 의 labs 목록 참고)"; exit 1; }
DIR="modules/$MOD/faults/$(cut -d'|' -f2 <<<"$ROW" | xargs)"; TYPE=$(cut -d'|' -f5- <<<"$ROW" | sed 's/^ *//')
META=$(aws ssm get-parameter --name "$P/$LAB" --query Parameter.Value --output text 2>/dev/null) || META='{}'
STATE=$(jq -r '.state // empty' <<<"$META")
put_meta() { aws ssm put-parameter --name "$P/$LAB" --type String --overwrite --value "$1" >/dev/null; }
export LAB
ask_time() {  # $1=질문 → HH:MM 을 받아 오늘 날짜의 ISO 시각으로. 빈칸이면 지금
  local a; read -r -p "$1 (HH:MM, 빈칸이면 지금): " a 2>/dev/null </dev/tty || a=""
  if [[ "$a" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then TZ=Asia/Seoul date -d "$(TZ=Asia/Seoul date +%F) $a" '+%Y-%m-%dT%H:%M:%S%z'; else now; fi
}

case $ACTION in
retry)
  [ "$STATE" = rolled_back ] || { echo "❌ 재도전은 원복(rollback)한 Lab 에서만 할 수 있습니다. 현재 상태: ${STATE:-기록 없음}"; exit 1; }
  export VARIANT; VARIANT=$(aws ssm get-parameter --name "$P/$LAB/variant" --query Parameter.Value --output text 2>/dev/null)
  [ -n "$VARIANT" ] && [ "$VARIANT" != None ] || { echo "❌ 지난 주입의 변형 기록이 없습니다."; exit 1; }
  RETRY=1; ACTION=inject; STATE="" ;&
inject)
  [ "$STATE" = injected ] && { echo "❌ Lab $LAB 장애가 이미 주입되어 있습니다. 다시 하려면 rollback 을 먼저 실행하세요."; exit 1; }
  # 지난 시도의 원복 정보는 지운다
  OLD=$(aws ssm get-parameters-by-path --path "$P/$LAB" --query 'Parameters[].Name' --output text 2>/dev/null)
  [ -n "$OLD" ] && aws ssm delete-parameters --names $OLD >/dev/null
  bash "$ROOT/$DIR/inject.sh" >/dev/null || {
    echo "❌ 주입 실패 — 위 오류를 확인하세요. 일부 바뀐 설정을 되돌립니다."
    bash "$ROOT/$DIR/rollback.sh" >/dev/null 2>&1; exit 1; }
  T=$(now); ATT=$(( $(jq -r '.attempt // 0' <<<"$META") + 1 ))
  put_meta "$(jq -nc --arg l "$LAB" --arg d "$DIR" --arg t "$T" --argjson a "$ATT" --argjson r "${RETRY:-0}" --argjson h "$META" \
    '{lab:$l, fault:$d, state:"injected", injected_at:$t, attempt:$a}
     + (if $r == 1 then {retry:true, first_injected_at:($h.first_injected_at // $h.injected_at), first_rolled_back_at:$h.rolled_back_at} else {} end)')"
  if [ "${RETRY:-0}" = 1 ]; then
    echo "✅ 같은 변형을 다시 주입했습니다(재도전). 이번에는 해답 토글을 펼쳐 놓고 자기 손으로 해결하세요."
  else
    echo "✅ 장애를 주입했습니다. 주입 시각을 기록표의 기준으로 적고 5단계 관찰을 시작하세요."
  fi
  echo "   장애 유형: $TYPE"
  echo "   주입 시각: $T" ;;
done)
  [ "$STATE" = injected ] || { echo "❌ Lab $LAB 에 진행 중인 주입 기록이 없습니다."; exit 1; }
  echo "주입 시각: $(jq -r .injected_at <<<"$META")"
  A=$(ask_time "장애를 처음 알아챈 시각(장애 인지 시각)"); C=$(ask_time "원인을 확정한 시각(원인 확정 시각)")
  put_meta "$(jq -c --arg t "$(now)" --arg a "$A" --arg c "$C" '.state="resolved" | .resolved_at=$t | .aware_at=$a | .cause_at=$c' <<<"$META")"
  echo "✅ 해결 기록을 남겼습니다(인지 $A · 원인 확정 $C · 복구 $(now))."
  echo "   해답 토글로 원인을 대조하고 런북(~/opslab-work/$MOD/runbook-$LAB.md)을 쓴 뒤: bash ~/opslab/common/review.sh $LAB" ;;
rollback)
  [ "$STATE" = injected ] || { echo "❌ Lab $LAB 에 원복할 주입 기록이 없습니다."; exit 1; }
  read -r -p "원복하면 이 Lab의 진단 기회가 끝납니다. 계속할까요? (y/N) " a; [ "$a" = y ] || exit 1
  bash "$ROOT/$DIR/rollback.sh" || { echo "❌ 원복 중 오류 — cleanup.sh 로 그날 리소스를 정리하고 시작 템플릿과 그날 구축을 다시 하세요."; exit 1; }
  put_meta "$(jq -c --arg t "$(now)" '.state="rolled_back" | .rolled_back_at=$t' <<<"$META")"
  echo "✅ 원복했습니다. 원복은 실패가 아닙니다 — 재도전으로 끝내세요:"
  echo "   bash ~/opslab/common/inject.sh retry $LAB   (같은 변형을 다시 주입 → 해답을 보며 직접 해결 → verify.sh → inject.sh done $LAB)" ;;
esac
