#!/bin/bash
# gitops 모듈 장애 스크립트 공통: 공통 함수 + EKS 함수 + gitops 함수(functions.sh) + 내 Fork·오늘 브랜치 찾기
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
source "$D/functions.sh"
NS=$APP_NS; DEP=opslab-app
R=$(fork_repo); B=$(fork_branch)
[ -n "$R" ] && [ -n "$B" ] || { echo "루트 앱(opslab-root)이 없습니다. 1단계 구축 4(App of Apps)를 먼저 끝내세요."; exit 3; }
GH_T=$(gh_token); [ -n "$GH_T" ] || { echo "GitHub 토큰 시크릿(opslab/github-token)이 없습니다."; exit 3; }
export GH_T
PV=gitops/envs/prod/values.yaml; PA=gitops/apps/templates/prod.yaml   # 운영 값 파일, 운영 앱 정의
# 영향 범위: 내 Fork 의 오늘 브랜치(커밋 추가 — 원복은 주입 전 커밋으로 브랜치를 되돌림), app 네임스페이스의 샘플 앱,
#           argocd 네임스페이스의 Argo CD 구성 요소·저장소 등록. 다른 브랜치·main·원본 저장소와 kube-system 은 바꾸지 않는다.
set -e   # 주입 명령 하나라도 실패하면 즉시 멈춘다(common/inject.sh 가 원복하고 실패를 알린다)
base_save() { save base "$(gh_head "$R" "$B")"; }             # 주입 전 브랜치 끝 커밋(원복 기준)
commit() { gh_edit "$R" "$B" "$1" "$2" "$3"; }                # $1=파일 $2=커밋 메시지 $3=sed 식
commit_append() { { gh_get "$R" "$B" "$1"; printf '%s\n' "$3"; } | gh_put "$R" "$B" "$1" "$2"; }   # $1=파일 $2=메시지 $3=끝에 덧붙일 줄
release_v2() { commit "$PV" "릴리스 v2" 's/^  APP_VERSION: v1$/  APP_VERSION: v2/'; }   # 새 버전 배포 커밋(반영됐는지 보는 표시)
kick() { app_refresh $APPS; }                                 # Argo CD 가 Git 을 바로 다시 보게(평소엔 1분마다)
wait_prod_rev() {  # 운영 앱이 브랜치 끝 커밋으로 동기화를 시작할 때까지(최대 $1초) — Git 을 다시 보라는 신호는 30초에 한 번만
  local h; h=$(gh_head "$R" "$B")
  for i in $(seq 1 $(( ${1:-180} / 5 ))); do
    [ "$(app_json opslab-prod | jq -r '.status.operationState.syncResult.revision // .status.sync.revision // ""')" = "$h" ] && return 0
    [ $((i % 6)) -eq 0 ] && kick; sleep 5
  done; return 1
}
wait_spec() {  # $1=jq 조건(운영 앱 Application 에 대해) — 루트 앱이 바뀐 앱 정의를 적용할 때까지(최대 180초)
  for i in $(seq 1 36); do app_json opslab-prod | jq -e "$1" >/dev/null && return 0; [ $((i % 6)) -eq 0 ] && kick; sleep 5; done
  echo "운영 앱 정의가 180초 안에 바뀌지 않았습니다: $1" >&2; return 1
}
restore_branch() {  # 원복: 브랜치를 주입 전 커밋으로 되돌리고, 멈춘 작업을 끝내고, 다시 동기화한다
  local b; b=$(load base)
  [ -n "$b" ] && [ "$b" != None ] && gh_reset "$R" "$B" "$b" && echo "  브랜치 $B → ${b:0:7} (주입 전 커밋)"
  for a in $APPS; do app_terminate "$a"; done
  kick; sleep 10; app_sync opslab-root; sleep 15; app_sync opslab-prod; app_sync opslab-dev
  apps_wait 300 && echo "  Argo CD 앱 3개 Synced·Healthy, 운영 앱이 브랜치 끝 커밋 반영" || echo "  ⚠️ 아직 Synced·Healthy 가 아닙니다: $(app_line opslab-prod) — 1~2분 뒤 verify.sh"
}
