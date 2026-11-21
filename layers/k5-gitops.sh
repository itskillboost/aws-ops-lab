#!/bin/bash
# K5 층(GitOps = gitops 모듈 완료 상태) — start.sh 가 실행한다. 다시 실행해도 안전하다.
#   ① Argo CD 설치(미러 이미지·고정 차트, 화면은 내 PC IP 만 허용한 NLB) ② 내 Fork 등록(토큰은 Secrets Manager)
#   ③ 샘플 앱의 주인을 helm → Argo CD 로 ④ 루트 앱(App of Apps) → 자식 앱 opslab-prod(app)·opslab-dev(app-dev) ⑤ 모두 Synced·Healthy 확인
# gitops 모듈 1단계 구축 따라하기와 같은 명령이다(modules/gitops/full.sh 도 이 파일을 실행한다).
# 필요한 것: start.sh 가 만든 오늘 브랜치(GITOPS_BRANCH), ~/opslab-env.sh 의 GITHUB_REPO, Secrets Manager opslab/github-token
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../common/eks.sh"
source "$EKS_ROOT/modules/gitops/functions.sh"
: "${GITHUB_REPO:?~/opslab-env.sh 에 export GITHUB_REPO=<내 GitHub ID>/aws-ops-lab 가 없습니다}"
: "${GITOPS_BRANCH:?오늘 브랜치가 없습니다 — bash ~/opslab/common/fork.sh prepare <모듈ID>}"
kube_login

argocd_install || { echo "❌ Argo CD 설치 실패 — kubectl -n argocd get pods"; exit 1; }
echo "  Argo CD (argocd 네임스페이스)"
repo_register "$GITHUB_REPO" || exit 1
echo "  저장소 등록: https://github.com/$GITHUB_REPO (브랜치 $GITOPS_BRANCH)"
app_handover
root_render "$GITHUB_REPO" "$GITOPS_BRANCH" | kubectl apply -f - >/dev/null || { echo "❌ 루트 앱 생성 실패"; exit 1; }
echo "  루트 앱 opslab-root → 자식 앱 opslab-prod·opslab-dev"
apps_wait 420 || { echo "❌ Argo CD 앱이 Synced·Healthy 가 되지 않음:"; for a in $APPS; do echo "    $a $(app_line "$a")"; done; exit 1; }
for a in $APPS; do echo "    $a $(app_line "$a")"; done
