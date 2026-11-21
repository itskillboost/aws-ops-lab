#!/bin/bash
# gitops 모듈(GitOps·Argo CD) 함수 — K5 층(layers/k5-gitops.sh)·장애 스크립트(lib.sh)·verify·check 가 함께 쓴다.
# 미리 common/eks.sh 를 source 해 두어야 한다(SID·CLUSTER·APP_NS·EKS_ROOT·img).
source "$EKS_ROOT/common/gh.sh"
ACCT=$(aws sts get-caller-identity --query Account --output text)
K5="$EKS_ROOT/layers/k5-gitops"
APPS="opslab-root opslab-prod opslab-dev"   # 루트 앱(목차)과 자식 앱(운영·개발)

# ── Argo CD 앱 상태 읽기·조작(kubectl 만으로 — argocd CLI 로그인 없이도 동작)
app_json() { kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null; }
app_line() {  # $1=앱 → "동기화 건강 리비전(7) 작업상태" (없으면 "없음")
  app_json "$1" | jq -r '"\(.status.sync.status // "-") \(.status.health.status // "-") \((.status.sync.revision // "-")[0:7]) \(.status.operationState.phase // "-")"' 2>/dev/null || echo "없음"
}
fork_repo()   { kubectl -n argocd get applications.argoproj.io opslab-root -o jsonpath='{.spec.source.repoURL}' 2>/dev/null | sed -E 's#^https://github.com/##; s#\.git$##'; }
fork_branch() { kubectl -n argocd get applications.argoproj.io opslab-root -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null; }
app_refresh() { local a; for a in "$@"; do kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1; done; }
app_sync() {  # $1=앱 — 지금 바로 동기화(argocd app sync 와 같은 일)
  kubectl -n argocd patch applications.argoproj.io "$1" --type merge \
    -p '{"operation":{"initiatedBy":{"username":"opslab"},"sync":{"prune":true,"syncStrategy":{"hook":{}}}}}' >/dev/null 2>&1
}
app_terminate() {  # $1=앱 — 진행 중인 동기화 작업을 멈춘다(argocd app terminate-op 와 같은 일)
  [ "$(app_json "$1" | jq -r '.status.operationState.phase // ""')" = Running ] || return 0
  kubectl -n argocd patch applications.argoproj.io "$1" --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}' >/dev/null 2>&1
  for i in $(seq 1 12); do [ "$(app_json "$1" | jq -r '.status.operationState.phase // ""')" != Terminating ] && break; sleep 5; done
}
apps_wait() {  # [$1=초] — 세 앱이 모두 Synced·Healthy 이고 운영 앱이 브랜치 끝 커밋을 반영(마지막 작업 성공)할 때까지 기다린다
  local t=${1:-300} head a ok
  for i in $(seq 1 $((t / 10))); do
    head=$(gh_head "$(fork_repo)" "$(fork_branch)"); ok=1
    for a in $APPS; do [[ "$(app_line "$a")" == "Synced Healthy "* ]] || ok=0; done
    [ "$ok" = 1 ] && [ "$(app_json opslab-prod | jq -r '.status.sync.revision // ""')" = "$head" ] \
      && [[ "$(app_json opslab-prod | jq -r '.status.operationState.phase // "Succeeded"')" == Succeeded ]] && return 0
    sleep 10
  done; return 1
}

# ── 구축(K5 층과 따라하기가 같은 순서로 쓴다)
argocd_install() {  # Argo CD — 미러 이미지·고정 차트, 화면(UI)은 NLB 로 열되 내 PC IP 만 허용
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace argocd course=opslab --overwrite >/dev/null
  helm upgrade --install argocd "$EKS_ROOT/vendor/charts/argo-cd" -n argocd --wait --timeout 10m -f "$K5/argocd-values.yaml" \
    --set global.image.repository="$(img_repo argocd)" --set global.image.tag="$(img_tag argocd)" \
    --set redis.image.repository="$(img_repo argocd-redis)" --set redis.image.tag="$(img_tag argocd-redis)" \
    --set-string "server.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-additional-resource-tags=Course=opslab\,Module=gitops\,Owner=$SID" \
    --set "server.service.loadBalancerSourceRanges={${HEADLAMP_SOURCE:-127.0.0.1/32}}" >/dev/null
}
repo_secret() {  # $1=저장소 → 그 주소로 등록된 Argo CD 저장소 Secret 이름(argocd repo add 로 만들면 repo-<숫자>, K5 층은 repo-fork)
  kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository -o json 2>/dev/null \
    | jq -r --arg u "https://github.com/$1.git" '.items[] | select((.data.url // "" | @base64d) == $u) | .metadata.name' | head -1
}
repo_register() {  # $1=저장소 — 내 Fork 를 Argo CD 에 등록(토큰은 Secrets Manager). 이미 있으면 토큰만 새 값으로 바꾼다
  local r=${1:?저장소} t n; t=$(gh_token); [ -n "$t" ] || { echo "❌ GitHub 토큰 시크릿(opslab/github-token)이 없습니다"; return 1; }
  n=$(repo_secret "$r"); n=${n:-repo-fork}
  kubectl -n argocd create secret generic "$n" --from-literal=type=git --from-literal=url="https://github.com/$r.git" \
    --from-literal=username=x-access-token --from-literal=password="$t" --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository course=opslab -o yaml | kubectl apply -f - >/dev/null
}
app_handover() {  # 샘플 앱의 주인을 helm 에서 Argo CD 로 — helm 설치 기록만 지운다(리소스는 그대로, Argo CD 가 이어받는다)
  kubectl -n "$APP_NS" delete secret -l owner=helm,name=opslab-app --ignore-not-found >/dev/null
}
root_render() {  # $1=저장소 $2=브랜치 → 루트 앱 매니페스트(gitops/root.yaml 에 학번·계정·이미지를 채운 것)
  sed -e "s#__REPO__#$1#g" -e "s#__BRANCH__#$2#g" -e "s#__SID__#$SID#g" -e "s#__ACCT__#$ACCT#g" \
      -e "s#__APP_REPO__#$(img_repo app)#g" -e "s#__APP_TAG__#$(img_tag app)#g" -e "s#__BUSYBOX__#$(img busybox)#g" \
      "$EKS_ROOT/gitops/root.yaml"
}
argocd_pass() { kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d; }
