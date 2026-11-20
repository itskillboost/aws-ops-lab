#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/podnet/baseline/verify.sh
# 부하 파드(load.sh pod alb)가 1분 이상 돌고 있어야 [6] 판정이 정확하다. 통과하면 기준값을 ~/opslab-work/podnet/baseline.txt 에 남긴다.
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/podnet
OUT=$(verify_main "podnet baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# podnet 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## 서브넷별 남은 IP"; aws ec2 describe-subnets --filters Name=tag:Owner,Values="$SID" --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,AvailableIpAddressCount]' --output text
    echo "## 파드 IP"; kubectl -n "$NS" get pods -o wide --no-headers | awk '{print $1, $6, $7}'
    echo "## Service·Endpoints"; kubectl -n "$NS" get svc,endpoints "$DEP" -o wide
  } > ~/opslab-work/podnet/baseline.txt
  echo "기준값을 ~/opslab-work/podnet/baseline.txt 에 기록했습니다."
fi
exit $RC
