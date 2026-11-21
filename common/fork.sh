#!/bin/bash
# 내 Fork(GitHub) 준비 도구 — GitOps 를 쓰는 날(gitops·image·heal)에 start.sh 가 자동으로 실행한다. 직접 실행해도 안전하다.
#   bash ~/opslab/common/fork.sh prepare gitops   ① Fork 를 원본과 동기화 ② 원본 과정 태그에서 오늘 브랜치 opslab/gitops-<날짜> 를 만든다
#   bash ~/opslab/common/fork.sh status           내 Fork·오늘 브랜치·최근 커밋 보기
#   bash ~/opslab/common/fork.sh clone            오늘 브랜치를 ~/fork 에 내려받는다(git push 할 때 토큰은 Secrets Manager 에서 자동으로 읽는다)
# 필요한 것(Day 0): ~/opslab-env.sh 의 export GITHUB_REPO=<내 GitHub ID>/aws-ops-lab, Secrets Manager 의 opslab/github-token(Fork 쓰기 권한)
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
source "$ROOT/common/eks.sh"; source "$ROOT/common/gh.sh"
R=${GITHUB_REPO:-}; UP=$(cval upstream_repo); TAG=${GITOPS_BASE:-$(cval gitops_base_tag)}
[ -n "$R" ] || { echo "❌ ~/opslab-env.sh 에 export GITHUB_REPO=<내 GitHub ID>/aws-ops-lab 가 없습니다 (Day 0 따라하기 5단계)"; exit 1; }
GH_T=$(gh_token); [ -n "$GH_T" ] || { echo "❌ GitHub 토큰 시크릿(opslab/github-token)이 없습니다 (Day 0 따라하기 5단계)"; exit 1; }
export GH_T
envset() { grep -q "^export $1=" ~/opslab-env.sh 2>/dev/null && sed -i "s#^export $1=.*#export $1=$2#" ~/opslab-env.sh || echo "export $1=$2" >> ~/opslab-env.sh; }

case "${1:-status}" in
prepare)
  MOD=${2:?모듈 ID}; B="opslab/$MOD-$(TZ=Asia/Seoul date +%F)"
  P=$(gh_api GET "/repos/$R") || { echo "❌ Fork $R 를 찾지 못했습니다 — 이름(GITHUB_REPO)과 토큰의 저장소 범위를 확인하세요"; exit 1; }
  [ "$(jq -r .permissions.push <<<"$P")" = true ] || { echo "❌ 토큰에 $R 쓰기 권한이 없습니다 — 토큰 권한 Contents: Read and write"; exit 1; }
  # ① 동기화: Fork 는 원본이 바뀌어도 저절로 따라오지 않는다 → GitHub "Sync fork" 를 API 로 누른다
  if [ "$R" != "$UP" ]; then
    out=$(echo '{"branch":"main"}' | gh_api POST "/repos/$R/merge-upstream") \
      && echo "  ① Fork 동기화: $(jq -r '.message // .merge_type' <<<"$out")" \
      || { echo "❌ Fork 동기화 실패: $(jq -r .message <<<"$out" 2>/dev/null)"
           echo "   ↳ 409(충돌): 내 Fork 의 main 에 직접 커밋한 것이 있습니다. GitHub 화면의 Sync fork → Discard commits 로 원본에 맞추세요."
           echo "   ↳ 403/404: 토큰이 만료됐거나 다른 저장소용입니다. 새 토큰을 만들어 aws secretsmanager put-secret-value --secret-id opslab/github-token 으로 바꾸세요."
           echo "   ↳ 422: Fork 의 기본 브랜치가 main 이 아니거나 이름을 바꿨습니다. GITHUB_REPO 를 확인하세요."; exit 1; }
  fi
  # ② 오늘 브랜치: 원본의 과정 태그(전날 장애 커밋이 남지 않은 깨끗한 시작점)에서 만든다. 이미 있으면 그대로 쓴다(이어서 하기)
  if [ -n "$(gh_head "$R" "$B")" ]; then
    echo "  ② 오늘 브랜치 $B 는 이미 있습니다 — 그대로 씁니다"
  else
    S=$(git ls-remote "https://github.com/$UP" "refs/tags/$TAG^{}" "refs/tags/$TAG" "refs/heads/$TAG" </dev/null | awk '{print $1; exit}')
    [ -n "$S" ] || { echo "❌ 원본 $UP 에 과정 태그 $TAG 가 없습니다 — 강사에게 알려 주세요"; exit 1; }
    jq -nc --arg r "refs/heads/$B" --arg s "$S" '{ref:$r, sha:$s}' | gh_api POST "/repos/$R/git/refs" >/dev/null \
      || { echo "❌ 브랜치 $B 를 만들지 못했습니다 (원본 커밋 ${S:0:7} 이 Fork 에 없으면 ① 동기화를 먼저 하세요)"; exit 1; }
    echo "  ② 오늘 브랜치 $B 생성 (원본 $TAG = ${S:0:7})"
  fi
  envset GITOPS_BRANCH "$B"
  echo "✅ Fork 준비 완료: https://github.com/$R/tree/$B  (Argo CD 는 이 브랜치만 봅니다)" ;;
status)
  B=${GITOPS_BRANCH:-}
  echo "== 내 Fork: https://github.com/$R"
  [ -n "$B" ] || { echo "  오늘 브랜치가 아직 없습니다 — bash ~/opslab/common/fork.sh prepare <모듈ID>"; exit 0; }
  echo "== 오늘 브랜치: $B  끝 커밋 $(gh_head "$R" "$B" | cut -c1-7)"
  gh_log "$R" "$B" 5 | sed 's/^/  /' ;;
clone)
  B=${GITOPS_BRANCH:?오늘 브랜치가 없습니다 — bash ~/opslab/common/fork.sh prepare <모듈ID>}; D=~/fork
  if [ -d "$D/.git" ]; then git -C "$D" fetch -q origin "$B" && git -C "$D" checkout -q -B "$B" "origin/$B"
  else git clone -q -b "$B" "https://github.com/$R" "$D"; fi || { echo "❌ 내려받기 실패"; exit 1; }
  # git push 할 때 토큰을 Secrets Manager 에서 읽어 건넨다(토큰이 화면·셸 기록에 남지 않는다)
  git -C "$D" config credential.helper '!f() { test "$1" = get || exit 0; echo username=x-access-token; echo "password=$(aws secretsmanager get-secret-value --secret-id opslab/github-token --query SecretString --output text)"; }; f'
  git -C "$D" config user.name "$SID"; git -C "$D" config user.email "$SID@opslab.local"
  echo "✅ ~/fork 에 $B 를 내려받았습니다. 고친 뒤: cd ~/fork && git commit -am '메시지' && git push" ;;
*) sed -n '3,6p' "$0" | sed 's/^#//'; exit 1 ;;
esac
