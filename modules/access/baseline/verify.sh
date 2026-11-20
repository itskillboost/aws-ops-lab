#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/access/baseline/verify.sh
# 부하 파드(load.sh pod alb)가 1분 이상 돌고 있어야 [8] 판정이 정확하다. 통과하면 기준값을 ~/opslab-work/access/baseline.txt 에 남긴다.
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/access
OUT=$(verify_main "access baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# access 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## 앱 서비스 계정 어노테이션"; kubectl -n "$NS" get sa opslab-app -o jsonpath='{.metadata.annotations}'; echo
    echo "## /aws 응답"; curl -s -m 10 "http://$(kubectl -n "$NS" get ingress "$DEP" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/aws"; echo
    echo "## Vault 상태"; vst | jq -c '{initialized,sealed,version}'
    echo "## 앱 파드 컨테이너"; kubectl -n "$NS" get pods -l app.kubernetes.io/name=opslab-app -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.initContainers[*].name}{" | "}{.spec.containers[*].name}{"\n"}{end}'
  } > ~/opslab-work/access/baseline.txt
  echo "기준값을 ~/opslab-work/access/baseline.txt 에 기록했습니다."
fi
exit $RC
