#!/bin/bash
# image 상태 조회 도우미 — review.yaml·check.sh 가 부른다.  bash ~/opslab/modules/image/state.sh <질문>
#   released  : 파이프라인 마지막 실행이 성공했고, 가장 최근 앱 커밋이 운영 앱 이미지에 들어 있으면 종료 코드 0
#   deployenv : 배포 프로젝트 환경변수가 오늘 브랜치·내 ECR·opslab/github-token 을 가리키면 0
#   gate      : 스캔 프로젝트 기준이 CRITICAL 이상 0개면 0
set -uo pipefail
: "${SID:?}"; source "$(dirname "$(readlink -f "$0")")/../../common/eks.sh"; kube_login
source "$EKS_ROOT/modules/image/functions.sh"; export GH_T=$(gh_token)
case "${1:-}" in
  released)
    read -r e s <<<"$(pipe_last)"; [ "$s" = Succeeded ] || { echo "파이프라인 마지막 실행: ${s:-없음}"; exit 1; }
    t=$(running_image); t=${t##*:}; src=$(latest_src)
    contains "$src" "$t" || { echo "최근 앱 커밋 ${src:0:7} 이 운영 이미지($t)에 없음"; exit 1; }
    [ "$(running_image)" = "$ECR_URI:$t" ] || { echo "운영 앱이 내 ECR 이미지가 아님: $(running_image)"; exit 1; } ;;
  deployenv)
    v=$(project_envget "$PD" | jq -r '.environmentVariables | map({(.name): .value}) | add')
    [ "$(jq -r .GITOPS_BRANCH <<<"$v")" = "$(fork_branch)" ] || { echo "GITOPS_BRANCH=$(jq -r .GITOPS_BRANCH <<<"$v") ≠ $(fork_branch)"; exit 1; }
    [ "$(jq -r .ECR_URI <<<"$v")" = "$ECR_URI" ] || { echo "ECR_URI=$(jq -r .ECR_URI <<<"$v") ≠ $ECR_URI"; exit 1; }
    [ "$(jq -r .GITHUB_TOKEN <<<"$v")" = opslab/github-token ] || { echo "GITHUB_TOKEN 시크릿=$(jq -r .GITHUB_TOKEN <<<"$v")"; exit 1; } ;;
  gate)
    v=$(project_envget "$PS" | jq -r '.environmentVariables | map({(.name): .value}) | add')
    [ "$(jq -r .GATE_SEVERITY <<<"$v")" = CRITICAL ] && [ "$(jq -r .GATE_MAX <<<"$v")" = 0 ] || { echo "기준 $(jq -r '.GATE_SEVERITY+" 이상 "+.GATE_MAX+"개"' <<<"$v")"; exit 1; } ;;
  *) sed -n '2,5p' "$0"; exit 2 ;;
esac
