# gitops 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="env fork argocd repo root envs sync load"
_go() { [ -n "${ACCT:-}" ] || source "$EKS_ROOT/modules/gitops/functions.sh"; export GH_T=${GH_T:-$(gh_token)}; }
stage_env() {       # 사전 조건: K4 층(클러스터·샘플 앱·ALB·Vault)과 내 Fork 준비
  kube_login && kubectl get ns default >/dev/null 2>&1 && ok "kubectl 접속(kubeconfig)" || { ng "kubectl 로 접속되지 않습니다" "bash ~/opslab/common/start.sh gitops"; return; }
  [ "$(kubectl -n app get deploy opslab-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" -ge 2 ] 2>/dev/null && ok "샘플 앱 파드 Ready" || ng "샘플 앱이 Ready 가 아닙니다" "bash ~/opslab/common/start.sh gitops (다시 실행하면 이어서 합니다)"
  kubectl -n vault get pod vault-0 >/dev/null 2>&1 && ok "Vault(K4 층)" || ng "Vault 가 없습니다" "bash ~/opslab/common/start.sh gitops"
  [ -n "${GITHUB_REPO:-}" ] && ok "내 Fork: $GITHUB_REPO" || ng "GITHUB_REPO 가 없습니다" "Day 0 따라하기 5단계 — echo 'export GITHUB_REPO=<내 ID>/aws-ops-lab' >> ~/opslab-env.sh"
  [ -n "${GITOPS_BRANCH:-}" ] && ok "오늘 브랜치: $GITOPS_BRANCH" || ng "오늘 브랜치가 없습니다" "bash ~/opslab/common/fork.sh prepare gitops && source ~/opslab-env.sh"
}
stage_fork() {      # 구축 1: Fork 와 오늘 브랜치 내려받기
  _go
  [ -n "$(gh_head "${GITHUB_REPO:-x}" "${GITOPS_BRANCH:-x}")" ] && ok "GitHub 에 오늘 브랜치가 있음" || ng "GitHub 에 오늘 브랜치가 없습니다" "bash ~/opslab/common/fork.sh prepare gitops"
  [ "$(git -C ~/fork rev-parse --abbrev-ref HEAD 2>/dev/null)" = "${GITOPS_BRANCH:-}" ] && ok "~/fork 가 오늘 브랜치" || ng "~/fork 가 없거나 다른 브랜치입니다" "구축 1 — bash ~/opslab/common/fork.sh clone"
  [ -f ~/fork/gitops/apps/templates/prod.yaml ] && ok "~/fork/gitops (앱 목록·환경 값)" || ng "~/fork/gitops 가 없습니다" "구축 1 — bash ~/opslab/common/fork.sh clone"
}
stage_argocd() {    # 구축 2: Argo CD 설치·접속
  _go; local c r
  for c in deploy/argocd-server deploy/argocd-repo-server statefulset/argocd-application-controller deploy/argocd-redis; do
    r=$(kubectl -n argocd get $c -o jsonpath='{.status.readyReplicas}' 2>/dev/null); [ "${r:-0}" -ge 1 ] && ok "${c#*/} Ready" || ng "${c#*/} 가 Ready 가 아닙니다" "구축 2 — helm upgrade --install argocd …"
  done
  kubectl -n argocd get svc argocd-server -o jsonpath='{.metadata.annotations}' 2>/dev/null | grep -q internet-facing && ok "화면(UI) 로드밸런서" || ng "argocd-server 가 로드밸런서가 아닙니다" "구축 2 — 설치 명령의 -f argocd-values.yaml"
  ARGOCD_OPTS="--port-forward --port-forward-namespace argocd --plaintext" argocd account get-user-info 2>/dev/null | grep -q 'Logged In: true' && ok "argocd CLI 로그인" || ng "argocd CLI 가 로그인되어 있지 않습니다" "bash ~/opslab/common/argocd.sh"
}
stage_repo() {      # 구축 3: 저장소 등록
  _go
  [ -n "$(repo_secret "${GITHUB_REPO:-x}")" ] && ok "Argo CD 에 내 Fork 등록됨" || ng "내 Fork 가 등록되지 않았습니다" "구축 3 — argocd repo add …"
}
stage_root() {      # 구축 4: App of Apps
  _go; local a
  [ "$(fork_branch)" = "${GITOPS_BRANCH:-}" ] && ok "루트 앱 opslab-root → 브랜치 $(fork_branch)" || { ng "루트 앱이 없거나 다른 브랜치를 봅니다" "구축 4 — kubectl apply -f ~/root-app.yaml"; return; }
  for a in $APPS; do [[ "$(app_line $a)" == "Synced Healthy "* ]] && ok "$a Synced·Healthy" || ng "$a: $(app_line $a)" "구축 4 — argocd app get $a"; done
  kubectl -n app get secret -l owner=helm,name=opslab-app -o name 2>/dev/null | grep -q . && ng "helm 설치 기록이 남아 있습니다(주인이 둘)" "구축 4 — kubectl -n app delete secret -l owner=helm,name=opslab-app" || ok "샘플 앱의 주인은 Argo CD 하나"
}
stage_envs() {      # 구축 5: dev·prod 환경 분리와 Git 변경 반영
  _go
  [ "$(kubectl -n app-dev get deploy opslab-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 1 ] && ok "개발 환경(app-dev) 파드 1개" || ng "개발 환경 파드가 없습니다" "구축 5 — argocd app get opslab-dev"
  kubectl -n app-dev get deploy opslab-app -o json 2>/dev/null | jq -e '[.spec.template.spec.containers[0].env[]|select(.name=="APP_VERSION")|.value][0] | test("^dev-")' >/dev/null \
    && ok "Git 커밋이 개발 환경에 반영됨(APP_VERSION dev-…)" || ng "개발 환경 버전이 아직 dev 입니다" "구축 5 — ~/fork 에서 dev 값 고쳐 git push 후 argocd app get opslab-dev --refresh"
}
stage_sync() {      # 구축 6: 동기화 정책
  _go
  app_json opslab-prod | jq -e '.spec.syncPolicy.automated.selfHeal and .spec.syncPolicy.automated.prune' >/dev/null && ok "운영 앱 자동 동기화(prune·selfHeal)" || ng "운영 앱 자동 동기화가 꺼져 있습니다" "구축 6 — prod.yaml 의 syncPolicy"
  app_json opslab-prod | jq -e '[.spec.ignoreDifferences[]?.jsonPointers[]?] | index("/spec/replicas")' >/dev/null && ok "replicas 는 HPA 에 맡김(ignoreDifferences)" || ng "ignoreDifferences 가 없습니다" "구축 6"
  [ "$(kubectl -n app get deploy opslab-app -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="APP_VERSION")].value}')" = v1 ] && ok "수동 변경(APP_VERSION=manual)이 자동 치유로 v1 로 돌아옴" || ng "운영 앱 버전이 v1 이 아닙니다" "구축 6 — 20초 기다린 뒤 다시 확인"
}
stage_load() {      # 2단계(정상 상태 정의)
  kubectl -n app get deploy opslab-load -o jsonpath='{.spec.template.spec.containers[0].env[0].value}' 2>/dev/null | grep -q elb.amazonaws.com \
    && ok "부하 파드가 ALB 로 요청 중" || ng "부하 파드가 없거나 ALB 로 보내지 않습니다" "2단계 — bash ~/opslab/common/load.sh pod alb"
  [ -f ~/opslab-work/gitops/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/gitops/baseline/verify.sh"
}
