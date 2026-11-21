#!/bin/bash
# gitops-6 argocd — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: argocd 네임스페이스의 repo-server(①)·저장소 등록 Secret repo-fork(②)·application-controller(③), 내 Fork 오늘 브랜치(릴리스 v2 커밋)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); base_save
case $V in
  1) # repo-server(Git 을 읽어 매니페스트를 만드는 부품) 중지
     kubectl -n argocd scale deploy argocd-repo-server --replicas=0 >/dev/null ;;
  2) # 저장소 자격증명 만료 — 등록된 토큰이 폐기된 옛 토큰으로 바뀌었다
     kubectl -n argocd patch secret "$(repo_secret "$R")" --type merge -p "{\"stringData\":{\"password\":\"github_pat_11EXPIRED0000000000000000_opslab$RANDOM\"}}" >/dev/null ;;
  3) # application-controller(감시원) 복제본 0 — 아무도 Git 과 클러스터를 비교하지 않는다
     kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 >/dev/null ;;
esac
sleep 5
release_v2    # 개발팀이 릴리스 v2 를 커밋 — Argo CD 가 고장 나 있어 반영되지 않는다
kick
record $V
