#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/workload/baseline/verify.sh
# 부하 파드(load.sh pod)가 1분 이상 돌고 있어야 [4] 판정이 정확하다. 통과하면 기준값을 ~/opslab-work/workload/baseline.txt 에 남긴다.
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/workload
OUT=$(verify_main "workload baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# workload 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## 파드 자원 사용량(kubectl top)"; kubectl -n "$NS" top pods 2>/dev/null; } > ~/opslab-work/workload/baseline.txt
  echo "기준값을 ~/opslab-work/workload/baseline.txt 에 기록했습니다."
fi
exit $RC
