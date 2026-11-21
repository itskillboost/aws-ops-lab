# image 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="env fork ecr conn build pipe release load"
_im() { [ -n "${PIPE:-}" ] || source "$EKS_ROOT/modules/image/functions.sh"; export GH_T=${GH_T:-$(gh_token)}; }
stage_env() {       # 사전 조건: K5 층(Argo CD·App of Apps)·주변 구성 스택·내 Fork
  kube_login && kubectl get ns default >/dev/null 2>&1 && ok "kubectl 접속(kubeconfig)" || { ng "kubectl 로 접속되지 않습니다" "bash ~/opslab/common/start.sh image"; return; }
  _im; local a
  for a in $APPS; do [[ "$(app_line $a)" == "Synced Healthy "* ]] && ok "Argo CD 앱 $a Synced·Healthy" || ng "$a: $(app_line $a)" "bash ~/opslab/common/start.sh image (다시 실행하면 이어서 합니다)"; done
  [ -n "${IMAGE_BUILD_ROLE_ARN:-}" ] && aws iam get-role --role-name "$SID-image-build-role" >/dev/null 2>&1 && ok "주변 구성 스택($SID-image-env): 역할 2개·산출물 버킷" || ng "주변 구성 스택이 없거나 변수를 안 불러왔습니다" "bash ~/opslab/common/start.sh image && source ~/opslab-env.sh"
  [ -n "${GITOPS_BRANCH:-}" ] && ok "오늘 브랜치: $GITOPS_BRANCH" || ng "오늘 브랜치가 없습니다" "bash ~/opslab/common/fork.sh prepare image && source ~/opslab-env.sh"
}
stage_fork() {      # 구축 1: 오늘 브랜치 내려받기와 파이프라인 파일 보기
  _im
  [ "$(git -C ~/fork rev-parse --abbrev-ref HEAD 2>/dev/null)" = "${GITOPS_BRANCH:-}" ] && ok "~/fork 가 오늘 브랜치" || ng "~/fork 가 없거나 다른 브랜치입니다" "구축 1 — bash ~/opslab/common/fork.sh clone"
  [ -f ~/fork/pipeline/buildspec-build.yml ] && [ -f ~/fork/pipeline/buildspec-scan.yml ] && [ -f ~/fork/pipeline/buildspec-deploy.yml ] && ok "~/fork/pipeline 빌드 명세 3개" || ng "~/fork/pipeline 이 없습니다" "구축 1 — bash ~/opslab/common/fork.sh clone (강사: 과정 태그에 pipeline/ 이 있는지)"
}
stage_ecr() {       # 구축 2: 이미지 저장소
  _im; local j
  j=$(aws ecr describe-repositories --repository-names "$REPO_NAME" --query 'repositories[0]' --output json 2>/dev/null) || { ng "ECR 저장소 $REPO_NAME 이 없습니다" "구축 2 — aws ecr create-repository …"; return; }
  [ "$(jq -r .imageTagMutability <<<"$j")" = IMMUTABLE ] && ok "태그 불변(IMMUTABLE)" || ng "태그를 덮어쓸 수 있습니다(MUTABLE)" "구축 2 — aws ecr put-image-tag-mutability --image-tag-mutability IMMUTABLE"
  [ "$(jq -r .imageScanningConfiguration.scanOnPush <<<"$j")" = true ] && ok "푸시하면 스캔(scanOnPush)" || ng "scanOnPush 가 꺼져 있습니다" "구축 2 — aws ecr put-image-scanning-configuration"
  aws ecr get-lifecycle-policy --repository-name "$REPO_NAME" >/dev/null 2>&1 && ok "수명주기 정책 있음" || ng "수명주기 정책이 없습니다" "구축 2 — aws ecr put-lifecycle-policy"
}
stage_conn() {      # 구축 3: GitHub 연결
  _im; local s; s=$(conn_status)
  [ "$s" = AVAILABLE ] && ok "GitHub 연결 $CONN_NAME AVAILABLE" || ng "GitHub 연결이 ${s:-없음} 입니다" "구축 3 — 콘솔 [Developer Tools → 설정 → 연결]에서 $CONN_NAME → [보류 중인 연결 업데이트]"
}
stage_build() {     # 구축 4: CodeBuild 프로젝트 3개
  _im; local p
  for p in "$PB" "$PS" "$PD"; do project_exists "$p" && ok "CodeBuild 프로젝트 $p" || ng "$p 가 없습니다" "구축 4 — aws codebuild create-project …"; done
  project_exists "$PB" && [ "$(aws codebuild batch-get-projects --names "$PB" --query 'projects[0].environment.privilegedMode' --output text)" = True ] && ok "빌드 프로젝트 특권 모드(도커 빌드)" || ng "빌드 프로젝트 특권 모드가 꺼져 있습니다" "구축 4 — privilegedMode true"
}
stage_pipe() {      # 구축 5: 파이프라인과 첫 배포
  _im; local e s
  pipe_exists && ok "파이프라인 $PIPE" || { ng "파이프라인이 없습니다" "구축 5 — aws codepipeline create-pipeline …"; return; }
  read -r e s <<<"$(pipe_last)"; [ "$s" = Succeeded ] && ok "마지막 실행 성공" || ng "마지막 실행 ${s:-없음}" "구축 5 — 콘솔 파이프라인에서 실패한 단계의 [세부 정보]"
  [ "$(running_image | cut -d: -f1)" = "$ECR_URI" ] && ok "운영 앱이 내 ECR 이미지: $(running_image | cut -d: -f2)" || ng "운영 앱이 아직 강사 미러 이미지입니다" "구축 5 — 1~2분 뒤 argocd app get opslab-prod"
}
stage_release() {   # 구축 6: 앱 커밋 → 자동 배포
  _im; local t
  gh_get "$(fork_repo)" "$(fork_branch)" app/app.py | grep -q "hello from opslab ($SID)" && ok "앱 변경 커밋이 오늘 브랜치에 있음" || ng "앱 변경 커밋이 없습니다" "구축 6 — ~/fork/app/app.py 의 인사말을 고쳐 git commit·push"
  bash "$EKS_ROOT/modules/image/state.sh" released >/dev/null && ok "그 커밋이 운영 이미지에 들어감" || ng "앱 커밋이 아직 운영에 반영되지 않았습니다" "구축 6 — 5분 뒤 다시 확인. 파이프라인 실행 목록에 새 실행이 없으면 GitHub 앱이 내 계정에 설치됐는지(막혔을 때 표)"
}
stage_load() {      # 2단계(정상 상태 정의)
  kubectl -n app get deploy opslab-load -o jsonpath='{.spec.template.spec.containers[0].env[0].value}' 2>/dev/null | grep -q elb.amazonaws.com \
    && ok "부하 파드가 ALB 로 요청 중" || ng "부하 파드가 없거나 ALB 로 보내지 않습니다" "2단계 — bash ~/opslab/common/load.sh pod alb"
  [ -f ~/opslab-work/image/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/image/baseline/verify.sh"
}
