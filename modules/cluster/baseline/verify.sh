#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/cluster/baseline/verify.sh
# 부하 파드(load.sh pod)가 1분 이상 돌고 있어야 [4] 판정이 정확하다. 통과하면 기준값을 ~/opslab-work/cluster/baseline.txt 에 남긴다.
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/cluster
OUT=$(verify_main "cluster baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# cluster 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## 노드 자원 사용량(kubectl top nodes)"; kubectl top nodes 2>/dev/null
    echo "## 노드 상태 조건"; kubectl get nodes -o custom-columns='NODE:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,MEM:.status.conditions[?(@.type=="MemoryPressure")].status,DISK:.status.conditions[?(@.type=="DiskPressure")].status,PID:.status.conditions[?(@.type=="PIDPressure")].status'
  } > ~/opslab-work/cluster/baseline.txt
  echo "기준값을 ~/opslab-work/cluster/baseline.txt 에 기록했습니다."
fi
exit $RC
