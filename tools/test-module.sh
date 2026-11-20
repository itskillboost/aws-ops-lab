#!/bin/bash
# 모듈 독립 시험 (강사·작성자용) — 과정에 넣기 전에 모듈이 혼자서 동작하는지 확인한다.
#   SID=s00 bash ~/opslab/tools/test-module.sh cmp
# 순서: 정리 → 환경 층 배포(builds 층까지 + 모듈 env/done) → baseline verify → 모든 Lab·모든 변형 주입→원복 → 정리
#   DEEP=<초> 이면 주입 후·원복 후 그 초만큼 기다려 장애 verify 가 각각 실패·통과하는지도 본다(증상 검증).
#   SKIP_START=1 이면 앞의 정리·배포를 건너뛰고 지금 환경으로 시험한다(따라하기 명령 검증용).
#   RETRY=1 이면 원복 뒤 재도전(retry) → 해결(rollback.sh 를 해답 조치로 사용) → done → review.sh 까지 시험한다(review ❌ 0개여야 통과).
#   LABS="data-4 data-6" 이면 그 Lab만, VARIANTS="3" 이면 그 변형만 시험한다(부분 재시험). SKIP_CLEAN=1 이면 끝의 정리를 건너뛴다.
# 계정에 L0 층(<학번>-l0)이 있어야 한다. 부하 도구는 돌리지 않으므로 "요청 수 0건" FAIL 은 무시한다.
set -uo pipefail
: "${SID:?SID 를 지정하세요. 예) SID=s00 bash tools/test-module.sh cmp}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}" SID
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
MOD=${1:?모듈 ID}; MY="$ROOT/modules/$MOD/module.yaml"
[ -f "$MY" ] || { echo "모듈 없음: $MOD"; exit 1; }
LOG=~/test-$MOD-$(date +%m%d-%H%M).log; FAILS=0
say() { echo "$*" | tee -a "$LOG"; }
judge() {  # verify 출력에서 '요청 수 0건' 외 FAIL 개수
  grep '\[FAIL\]' | grep -vc '요청 수 0건' || true
}

say "== $(date '+%F %T') 모듈 시험: $MOD ($SID)"
if [ -z "${SKIP_START:-}" ]; then   # SKIP_START=1: 이미 구축한 환경(예: 따라하기 명령으로 직접 구축)을 그대로 시험
  echo "$SID" | bash "$ROOT/common/cleanup.sh" >>"$LOG" 2>&1
  bash "$ROOT/common/start.sh" "$MOD" full 2>&1 | tee -a "$LOG" | tail -1
  say "-- 앱 기동 대기 3분"; sleep 180
fi
# EKS 모듈: 부하 파드를 켠다(ALB 가 없는 날의 부하 도구)
grep -qE '^requires: *K' "$MY" && { bash "$ROOT/common/load.sh" pod >>"$LOG" 2>&1; sleep 75; }

n=$(bash "$ROOT/modules/$MOD/baseline/verify.sh" 2>&1 | tee -a "$LOG" | judge)
say "baseline verify: FAIL ${n} (요청 수 제외)"; [ "$n" -eq 0 ] || FAILS=$((FAILS+1))

grep -E '^ *- *[a-z]+-[0-9]+ *\|' "$MY" | while IFS='|' read -r lab fault vars level type; do
  lab=$(sed 's/^ *- *//' <<<"$lab" | xargs)
  vars=$(xargs <<<"$vars"); fault=$(xargs <<<"$fault")
  [ -n "${LABS:-}" ] && [[ " $LABS " != *" $lab "* ]] && continue
  for v in $(seq 1 "$vars"); do
    [ -n "${VARIANTS:-}" ] && [[ " $VARIANTS " != *" $v "* ]] && continue
    r=$(VARIANT=$v bash "$ROOT/common/inject.sh" "$lab" </dev/null 2>&1 | grep -c '✅')
    d=""; if [ -n "${DEEP:-}" ] && [ "$r" -ge 1 ]; then   # DEEP=1: 주입 후 verify 가 실패하는지(증상이 나는지)
      sleep "$DEEP"; bash "$ROOT/modules/$MOD/faults/$fault/verify.sh" >>"$LOG" 2>&1 && d=" 증상=없음!" || d=" 증상=있음"; fi
    b=$(echo y | bash "$ROOT/common/inject.sh" rollback "$lab" 2>&1 | grep -c '✅ 원복')
    if [ -n "${DEEP:-}" ] && [ "$b" -ge 1 ]; then          # 원복 후 verify 가 통과하는지
      sleep "$DEEP"; bash "$ROOT/modules/$MOD/faults/$fault/verify.sh" >>"$LOG" 2>&1 && d="$d 원복판정=통과" || d="$d 원복판정=실패!"; fi
    if [ -n "${RETRY:-}" ] && [ "$b" -ge 1 ]; then         # 재도전 → 해결 → 기록 → 검토
      W=~/opslab-work/$MOD; mkdir -p "$W"
      printf '# 가설: %s\n- 작성 시각: 시험\n- 파드 상태가 바뀔 것이다\n- 재시작이 늘 것이다\n- 응답이 실패할 것이다\n- describe·logs --previous·events 순으로 본다\n' "$lab" > "$W/hypothesis-$lab.md"
      printf '# 런북\n## 1. 증상\n시험 증상\n## 2. 확인 순서\nkubectl describe pod, kubectl logs --previous, events, kubectl get events --sort-by=.lastTimestamp, describe node, systemctl status kubelet, journalctl -u kubelet, Logs Insights authenticator audit\n## 3. 원인\n시험 원인 requests nodeSelector taint\n## 4. 조치\n시험 조치\n## 5. 재발 방지\nstartup liveness readiness 역할 구분, 스케줄 확인, 노드 알람 모니터링\n' > "$W/runbook-$lab.md"
      t=$(bash "$ROOT/common/inject.sh" retry "$lab" </dev/null 2>&1 | grep -c '✅'); sleep "${DEEP:-30}"
      LAB=$lab bash "$ROOT/modules/$MOD/faults/$fault/rollback.sh" >>"$LOG" 2>&1; sleep 80   # 해답 조치 대용
      bash "$ROOT/common/inject.sh" done "$lab" </dev/null >>"$LOG" 2>&1
      x=$(bash "$ROOT/common/review.sh" "$lab" 2>&1 | tee -a "$LOG" | grep -c '❌')
      d="$d 재도전=$t 검토❌=$x"; [ "$t" -ge 1 ] && [ "$x" -eq 0 ] || d="$d!"
    fi
    [ "$r" -ge 1 ] && [ "$b" -ge 1 ] && [[ "$d" != *"!"* ]] && res=OK || { res=XX; echo FAIL >> "$LOG.fail"; }
    say "$res $lab v$v ($fault) 주입=$r 원복=$b$d"
  done
done
[ -f "$LOG.fail" ] && FAILS=$((FAILS + $(wc -l < "$LOG.fail"))) && rm -f "$LOG.fail"

say "-- 원복 후 판정 대기 2분"; sleep 120
n=$(bash "$ROOT/modules/$MOD/baseline/verify.sh" 2>&1 | tee -a "$LOG" | judge)
say "원복 후 baseline verify: FAIL ${n} (요청 수 제외)"; [ "$n" -eq 0 ] || FAILS=$((FAILS+1))

[ -z "${SKIP_CLEAN:-}" ] && echo "$SID" | bash "$ROOT/common/cleanup.sh" >>"$LOG" 2>&1
say "== 결과: 실패 $FAILS 건 (상세 로그 $LOG)"
[ "$FAILS" -eq 0 ]
