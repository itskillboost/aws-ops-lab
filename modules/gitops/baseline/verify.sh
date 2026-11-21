#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/gitops/baseline/verify.sh
# 부하 파드(load.sh pod alb)가 1분 이상 돌고 있어야 [9] 판정이 정확하다. 통과하면 기준값을 ~/opslab-work/gitops/baseline.txt 에 남긴다.
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/gitops
OUT=$(verify_main "gitops baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# gitops 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## Argo CD 앱 (동기화 건강 리비전 마지막작업)"; for a in $APPS; do echo "$a $(app_line "$a")"; done
    echo "## 운영 앱 동기화 정책"; app_json opslab-prod | jq -c '{automated: .spec.syncPolicy.automated, syncOptions: .spec.syncPolicy.syncOptions, ignoreDifferences: .spec.ignoreDifferences}'
    echo "## 브랜치 최근 커밋"; GH_T=$(gh_token) gh_log "$(fork_repo)" "$(fork_branch)" 3
    echo "## 운영·개발 파드"; kubectl -n "$NS" get pods -l app.kubernetes.io/instance=opslab-app -o wide --no-headers; kubectl -n app-dev get pods --no-headers
  } > ~/opslab-work/gitops/baseline.txt
  echo "기준값을 ~/opslab-work/gitops/baseline.txt 에 기록했습니다."
fi
exit $RC
