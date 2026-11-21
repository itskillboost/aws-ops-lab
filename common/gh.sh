#!/bin/bash
# GitHub(수강생 Fork) 공통 함수 — fork.sh·K5 층·gitops 장애 스크립트·verify·review 가 source 한다.
# 토큰은 Secrets Manager opslab/github-token 에서만 읽고 화면·기록에 남기지 않는다(Day 0 따라하기 5단계에서 수강생이 넣는다).
GH_SECRET=opslab/github-token
gh_token() { aws secretsmanager get-secret-value --secret-id "$GH_SECRET" --query SecretString --output text 2>/dev/null; }

gh_api() {  # $1=METHOD $2=경로(/repos/…) [표준 입력=JSON 본문(METHOD 가 POST·PUT·PATCH·DELETE 일 때)] → 응답 본문, 실패(4xx·5xx)면 종료 코드 1
  local t out code body=()
  t=${GH_T:-$(gh_token)}; [ -n "$t" ] || { echo '{"message":"GitHub 토큰 시크릿(opslab/github-token)이 없습니다"}'; return 1; }
  case "$1" in POST|PUT|PATCH|DELETE) body=(--data-binary @-) ;; esac
  out=$(curl -sS -m 30 -w '\n%{http_code}' -X "$1" -H "Authorization: Bearer $t" -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" "${body[@]}" "https://api.github.com$2")
  code=${out##*$'\n'}; echo "${out%$'\n'*}"
  [ "${code:-0}" -ge 200 ] && [ "$code" -lt 400 ]
}

gh_head() {  # $1=저장소(id/aws-ops-lab) $2=브랜치 → 브랜치 끝 커밋 SHA
  gh_api GET "/repos/$1/git/ref/heads/$2" | jq -r '.object.sha // empty'
}
gh_reset() {  # $1=저장소 $2=브랜치 $3=SHA — 브랜치를 그 커밋으로 강제로 되돌린다(원복용)
  jq -nc --arg s "$3" '{sha:$s, force:true}' | gh_api PATCH "/repos/$1/git/refs/heads/$2" >/dev/null
}
gh_get() {  # $1=저장소 $2=브랜치 $3=파일 경로 → 파일 내용 (없으면 종료 코드 1)
  local j; j=$(gh_api GET "/repos/$1/contents/$3?ref=$2") || return 1
  jq -r .content <<<"$j" | base64 -d
}
gh_put() {  # $1=저장소 $2=브랜치 $3=파일 경로 $4=커밋 메시지, 표준 입력=새 내용 → 커밋(있으면 고치고 없으면 만든다)
  local sha c; sha=$(gh_api GET "/repos/$1/contents/$3?ref=$2" 2>/dev/null | jq -r '.sha // empty')
  c=$(base64 -w0)
  jq -nc --arg m "$4" --arg c "$c" --arg b "$2" --arg s "$sha" '{message:$m, content:$c, branch:$b} + (if $s != "" then {sha:$s} else {} end)' \
    | gh_api PUT "/repos/$1/contents/$3" >/dev/null
}
gh_edit() {  # $1=저장소 $2=브랜치 $3=파일 경로 $4=커밋 메시지 $5=sed 식 → 파일을 sed 로 고쳐 커밋. 바뀐 것이 없으면 실패
  local old new; old=$(gh_get "$1" "$2" "$3") || { echo "파일 없음: $3" >&2; return 1; }
  new=$(sed -E "$5" <<<"$old")
  [ "$new" != "$old" ] || { echo "바뀐 내용 없음: $3 ($5)" >&2; return 1; }
  printf '%s\n' "$new" | gh_put "$1" "$2" "$3" "$4"
}
gh_rm() {  # $1=저장소 $2=브랜치 $3=파일 경로 $4=커밋 메시지 → 파일 삭제 커밋
  local sha; sha=$(gh_api GET "/repos/$1/contents/$3?ref=$2" | jq -r '.sha // empty'); [ -n "$sha" ] || return 1
  jq -nc --arg m "$4" --arg b "$2" --arg s "$sha" '{message:$m, branch:$b, sha:$s}' | gh_api DELETE "/repos/$1/contents/$3" >/dev/null
}
gh_log() {  # $1=저장소 $2=브랜치 [$3=개수] → "짧은SHA 메시지" 목록(최신 먼저)
  gh_api GET "/repos/$1/commits?sha=$2&per_page=${3:-5}" | jq -r '.[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
}
