#!/bin/bash
# image 모듈 장애 스크립트 공통: 공통 함수 + EKS 함수 + image 함수(functions.sh) + 내 Fork·오늘 브랜치
D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$D/../../common/lib.sh"
source "$D/../../common/eks.sh"
kube_login || { echo "클러스터 $CLUSTER 에 접속하지 못했습니다."; exit 3; }
source "$D/functions.sh"
R=$(fork_repo); B=$(fork_branch)
[ -n "$R" ] && [ -n "$B" ] || { echo "루트 앱(opslab-root)이 없습니다. 환경 층(start.sh image)을 먼저 배포하세요."; exit 3; }
pipe_exists || { echo "파이프라인 $PIPE 이 없습니다. 1단계 구축 5를 먼저 끝내세요."; exit 3; }
GH_T=$(gh_token); [ -n "$GH_T" ] || { echo "GitHub 토큰 시크릿(opslab/github-token)이 없습니다."; exit 3; }
export GH_T
# 영향 범위: 내 Fork 의 오늘 브랜치(커밋 추가 — 원복은 주입 전 커밋으로 되돌림), CodeBuild 프로젝트 3개의 환경변수,
#           빌드 역할(<학번>-image-build-role)의 거부 정책 opslab-fault-deny, 장애용 시크릿 <학번>-image-old-token·장애용 브랜치.
#           main·원본 저장소·ECR 저장소 설정·클러스터 구성은 바꾸지 않는다.
set -e
DENY=opslab-fault-deny; BROLE="$SID-image-build-role"
base_save() {  # 주입 전 상태: 브랜치 끝 커밋, 프로젝트 3개 환경변수
  save base "$(gh_head "$R" "$B")"
  local p; for p in build scan deploy; do save "env-$p" "$(project_envget "$SID-image-$p" | jq -c .environmentVariables)"; done
}
commit() { gh_edit "$R" "$B" "$1" "$2" "$3"; }                # $1=파일 $2=커밋 메시지 $3=sed 식
release() {  # 개발팀의 새 릴리스 커밋(app/CHANGES.md 에 한 줄) — app/ 변경이라 파이프라인이 깨어난다
  { gh_get "$R" "$B" app/CHANGES.md 2>/dev/null || printf '# 변경 기록 — 릴리스마다 한 줄\n'; echo "- $(TZ=Asia/Seoul date '+%F %T') ${1:-주문 화면 문구 수정}"; } \
    | gh_put "$R" "$B" app/CHANGES.md "${1:-주문 화면 문구 수정}"
}
put_deny() {  # $1=액션 JSON 배열 — 빌드 역할에 인라인 거부 정책
  aws iam put-role-policy --role-name "$BROLE" --policy-name "$DENY" --policy-document \
    "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":$1,\"Resource\":\"*\"}]}"
}
restore() {  # 원복: 브랜치를 주입 전 커밋으로, 프로젝트 환경변수·역할을 주입 전으로 → 파이프라인을 한 번 돌려 정상 릴리스까지
  set +e
  local b p e r; b=$(load base)
  aws iam delete-role-policy --role-name "$BROLE" --policy-name "$DENY" 2>/dev/null && echo "  빌드 역할 거부 정책 삭제"
  for p in build scan deploy; do e=$(load "env-$p")
    [ -n "$e" ] && [ "$e" != None ] && aws codebuild update-project --name "$SID-image-$p" \
      --environment "$(project_envget "$SID-image-$p" | jq -c --argjson v "$e" '.environmentVariables = $v')" >/dev/null && echo "  $SID-image-$p 환경변수 → 주입 전"
  done
  [ -n "$b" ] && [ "$b" != None ] && [ "$(gh_head "$R" "$B")" != "$b" ] && gh_reset "$R" "$B" "$b" && echo "  브랜치 $B → ${b:0:7} (주입 전 커밋)"
  sleep 20                                    # IAM·프로젝트 변경이 퍼질 시간
  pipe_settle 900 >/dev/null                  # 장애 커밋으로 돌던 실행이 끝나기를 기다린 뒤
  e=$(pipe_start); r=$(pipe_wait "$e" 1500); echo "  파이프라인 다시 실행 ${e:0:8} → $r"
  [ "$r" = Succeeded ] || { echo "  ⚠️ 파이프라인이 성공하지 못했습니다:"; pipe_failed "$e" | sed 's/^/    /'; }
  deploy_wait 600 && echo "  운영 앱 이미지 $(running_image), Argo CD 앱 Synced·Healthy" || echo "  ⚠️ 운영 앱 반영이 아직입니다: $(running_image) — 1~2분 뒤 verify.sh"
}
