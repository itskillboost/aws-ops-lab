#!/bin/bash
# image 따라잡기(start.sh image full)와 시험(tools/test-module.sh image)이 쓰는 1단계 구축 명령 모음 — 따라하기 페이지의 순서와 같다.
#   구축 2 ECR 저장소 → 구축 3 GitHub 연결(콘솔 승인은 사람이) → 구축 4 CodeBuild 3개 → 구축 5 파이프라인(첫 실행) → 구축 6 앱 커밋 한 번
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"
source ~/opslab-env.sh
source "$EKS_ROOT/modules/image/functions.sh"
kube_login
: "${IMAGE_BUILD_ROLE_ARN:?<학번>-image-env 스택이 없습니다 — bash ~/opslab/common/start.sh image}"
export GH_T=$(gh_token)

echo "== 구축 2: 이미지 저장소 $REPO_NAME (태그 불변·푸시하면 스캔·수명주기)"
ecr_create || { echo "❌ ECR 저장소 생성 실패"; exit 1; }

echo "== 구축 3: GitHub 연결 $CONN_NAME"
conn_create
if [ "$(conn_status)" != AVAILABLE ]; then
  echo "   ⏳ 연결이 $(conn_status) 입니다 — 콘솔 [Developer Tools → 설정 → 연결] 에서 $CONN_NAME 을 골라 [보류 중인 연결 업데이트]로 GitHub 앱을 승인하세요. 10분 기다립니다."
  conn_wait 600 || { echo "❌ GitHub 연결이 AVAILABLE 이 아닙니다. 승인한 뒤 같은 명령을 다시 실행하세요."; exit 1; }
fi
echo "   연결 AVAILABLE"

echo "== 구축 4: CodeBuild 프로젝트 3개 ($PB · $PS · $PD)"
projects_create || { echo "❌ CodeBuild 프로젝트 생성 실패"; exit 1; }

echo "== 구축 5: 파이프라인 $PIPE (만들면 첫 실행이 바로 시작된다)"
if pipe_exists; then aws codepipeline update-pipeline --cli-input-json "$(pipeline_json | jq 'del(.tags)')" >/dev/null; E=$(pipe_start)
else aws codepipeline create-pipeline --cli-input-json "$(pipeline_json)" >/dev/null || { echo "❌ 파이프라인 생성 실패"; exit 1; }; sleep 15; E=$(pipe_last | awk '{print $1}'); fi
r=$(pipe_wait "$E" 1500); echo "   첫 실행 $E → $r"
[ "$r" = Succeeded ] || { echo "❌ 파이프라인 실패:"; pipe_failed "$E"; exit 1; }
deploy_wait 600 || { echo "❌ 운영 앱이 새 이미지로 바뀌지 않았습니다: $(running_image)"; exit 1; }
echo "   운영 앱 이미지: $(running_image)"

echo "== 구축 6: 앱 코드를 고쳐 커밋 → 파이프라인이 스스로 깨어나 새 이미지를 배포"
R=$(fork_repo); B=$(fork_branch); OLD=$(git_release Tag)
gh_get "$R" "$B" app/app.py | grep -q "hello from opslab ($SID)" \
  || gh_edit "$R" "$B" app/app.py "인사말에 학번 추가" "s/message=\"hello from opslab\"/message=\"hello from opslab ($SID)\"/" || exit 1
for i in $(seq 1 30); do [ "$(git_release Tag)" != "$OLD" ] && break; sleep 20; done
r=$(pipe_settle 900); echo "   두 번째 실행 → $r, 새 태그 $(git_release Tag)"
[ "$r" = Succeeded ] && [ "$(git_release Tag)" != "$OLD" ] || { echo "❌ 앱 커밋 뒤 파이프라인이 새 이미지를 배포하지 않았습니다"; pipe_failed "$(pipe_last | awk '{print $1}')"; exit 1; }
deploy_wait 600 || { echo "❌ 운영 앱이 새 이미지로 바뀌지 않았습니다: $(running_image)"; exit 1; }
echo "✅ image 구축 완료 — 운영 앱 이미지 $(running_image)"
