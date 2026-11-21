#!/bin/bash
# 내 Fork 오늘 브랜치(Argo CD 가 보는 브랜치)의 파일 내용을 보여 준다 — 학생이 진단에 쓰고, review.yaml 도 쓴다.
#   bash ~/opslab/modules/gitops/gitfile.sh gitops/envs/prod/values.yaml
#   bash ~/opslab/modules/gitops/gitfile.sh log      (최근 커밋 10개)
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"
source "$EKS_ROOT/common/gh.sh"
R=$(kubectl -n argocd get applications.argoproj.io opslab-root -o jsonpath='{.spec.source.repoURL}' 2>/dev/null | sed -E 's#^https://github.com/##; s#\.git$##')
B=$(kubectl -n argocd get applications.argoproj.io opslab-root -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null)
[ -n "$R" ] || { R=${GITHUB_REPO:?}; B=${GITOPS_BRANCH:?}; }
if [ "${1:?파일 경로 또는 log}" = log ]; then gh_log "$R" "$B" 10; else gh_get "$R" "$B" "$1"; fi
