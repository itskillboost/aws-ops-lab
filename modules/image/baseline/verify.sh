#!/bin/bash
# 2단계(정상 상태 정의) 판정 — 실행: bash ~/opslab/modules/image/baseline/verify.sh
# 부하 파드(load.sh pod alb)가 1분 이상 돌고 있어야 [7] 판정이 정확하다. 통과하면 기준값을 ~/opslab-work/image/baseline.txt 에 남긴다.
source "$(dirname "$(readlink -f "$0")")/../verify.sh"
mkdir -p ~/opslab-work/image
OUT=$(verify_main "image baseline(정상 상태 정의)"); RC=$?
echo "$OUT"
if [ $RC -eq 0 ]; then
  { echo "# image 정상 상태 기준값 — $(TZ=Asia/Seoul date '+%F %T')"; echo "$OUT" | grep PASS
    echo "## 파이프라인 최근 실행"; aws codepipeline list-pipeline-executions --pipeline-name "$PIPE" --max-items 3 \
      --query 'pipelineExecutionSummaries[].[pipelineExecutionId,status,startTime,sourceRevisions[0].revisionId]' --output text
    echo "## ECR 이미지(최근 순)"; aws ecr describe-images --repository-name "$REPO_NAME" --query 'reverse(sort_by(imageDetails,&imagePushedAt))[].[imageTags[0],imagePushedAt,imageScanStatus.status]' --output text
    echo "## 브랜치 최근 커밋"; GH_T=$(gh_token) gh_log "$(fork_repo)" "$(fork_branch)" 5
  } > ~/opslab-work/image/baseline.txt
  echo "기준값을 ~/opslab-work/image/baseline.txt 에 기록했습니다."
fi
exit $RC
