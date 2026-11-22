#!/bin/bash
# image-4 deploy-path — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 배포 프로젝트(<학번>-image-deploy)의 환경변수, 장애용 브랜치 opslab/image-old(①)·시크릿 <학번>-image-old-token(③), 내 Fork 오늘 브랜치(app/CHANGES.md)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); base_save
case $V in
  1) # 매니페스트를 커밋할 브랜치가 옛 브랜치로 되어 있다(지난 실습 설정을 복사) — 파이프라인은 성공, 운영은 그대로
     jq -nc --arg r refs/heads/opslab/image-old --arg s "$(load base)" '{ref:$r, sha:$s}' | gh_api POST "/repos/$R/git/refs" >/dev/null 2>&1 || true
     save oldbranch opslab/image-old
     project_envset "$PD" GITOPS_BRANCH opslab/image-old ;;
  2) # 매니페스트에 적는 이미지 주소가 옛 저장소 이름이다 — Git 에는 반영되지만 노드가 이미지를 받지 못한다
     project_envset "$PD" ECR_URI "$ACCT.dkr.ecr.$AWS_REGION.amazonaws.com/$SID-image-application" ;;
  3) # 커밋 토큰 만료 — 배포 프로젝트가 폐기된 옛 토큰 시크릿을 본다
     aws secretsmanager create-secret --name "$SID-image-old-token" --secret-string "github_pat_11EXPIRED0000000000000000_opslab$RANDOM" \
       --tags Key=Course,Value=opslab Key=Module,Value=image Key=Owner,Value=$SID >/dev/null 2>&1 \
       || aws secretsmanager put-secret-value --secret-id "$SID-image-old-token" --secret-string "github_pat_11EXPIRED0000000000000000_opslab$RANDOM" >/dev/null
     project_envset "$PD" GITHUB_TOKEN "$SID-image-old-token" SECRETS_MANAGER ;;
esac
sleep 5
release "장바구니 문구 수정"
record $V
