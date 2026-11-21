#!/bin/bash
# image 모듈(이미지 빌드와 배포 파이프라인) 함수 — full.sh(따라잡기)·장애 스크립트(lib.sh)·verify·check 가 함께 쓴다.
# 미리 common/eks.sh 를 source 해 두어야 한다. gitops 함수(Argo CD 앱 읽기·GitHub API)도 함께 불러온다.
source "$EKS_ROOT/modules/gitops/functions.sh"
IM="$EKS_ROOT/modules/image"
REPO_NAME="$SID-image-app"                                         # 내 이미지 저장소(ECR)
ECR_URI="$ACCT.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME"
PIPE="$SID-image-pipeline"; PB="$SID-image-build"; PS="$SID-image-scan"; PD="$SID-image-deploy"   # 파이프라인과 CodeBuild 프로젝트 3개
CONN_NAME="$SID-image-github"                                      # GitHub 연결(CodeConnections)
VALUES=gitops/apps/values.yaml                                     # 파이프라인이 이미지 태그를 커밋하는 파일
TAGS_KV="Key=Course,Value=opslab Key=Module,Value=image Key=Owner,Value=$SID"
mirror() { local r; r=$(cval registry); [ -n "$r" ] && [ "$r" != TBD ] && echo "$r" || echo public.ecr.aws/docker/library; }   # 기본 이미지를 받을 곳

# ── 1) 이미지 저장소: 태그 불변(같은 태그 덮어쓰기 금지)·푸시하면 스캔·수명주기(최근 20개 보관, 태그 없는 이미지는 1일 뒤 삭제)
lifecycle_json() {
  cat <<'J'
{"rules":[
 {"rulePriority":1,"description":"untagged after 1 day","selection":{"tagStatus":"untagged","countType":"sinceImagePushed","countUnit":"days","countNumber":1},"action":{"type":"expire"}},
 {"rulePriority":2,"description":"keep last 20 images","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":20},"action":{"type":"expire"}}
]}
J
}
ecr_create() {
  aws ecr describe-repositories --repository-names "$REPO_NAME" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$REPO_NAME" --image-tag-mutability IMMUTABLE \
      --image-scanning-configuration scanOnPush=true --tags $TAGS_KV >/dev/null
  aws ecr put-lifecycle-policy --repository-name "$REPO_NAME" --lifecycle-policy-text "$(lifecycle_json)" >/dev/null
}

# ── 2) GitHub 연결 — 만들면 PENDING. 콘솔에서 "보류 중인 연결 업데이트"를 눌러 GitHub 앱을 승인해야 AVAILABLE 이 된다(사람만 할 수 있음)
#    IMAGE_CONNECTION_ARN 이 있으면 그 연결을 쓴다(강사 리허설용 — 과정 내내 유지하는 연결)
conn_arn() {
  [ -n "${IMAGE_CONNECTION_ARN:-}" ] && { echo "$IMAGE_CONNECTION_ARN"; return; }
  aws codeconnections list-connections --provider-type-filter GitHub --query "Connections[?ConnectionName=='$CONN_NAME'].ConnectionArn | [0]" --output text 2>/dev/null | grep -v None
}
conn_status() { local a; a=$(conn_arn); [ -n "$a" ] && aws codeconnections get-connection --connection-arn "$a" --query Connection.ConnectionStatus --output text 2>/dev/null; }
conn_create() {
  [ -n "$(conn_arn)" ] || aws codeconnections create-connection --provider-type GitHub --connection-name "$CONN_NAME" \
    --tags Key=Course,Value=opslab Key=Module,Value=image Key=Owner,Value=$SID >/dev/null
}

# ── 3) CodeBuild 프로젝트 3개 — 빌드(이미지 만들기)·스캔(게이트)·배포(매니페스트 커밋). 빌드 명세는 Fork 의 pipeline/ 에 있다
project_env() {  # $1=build|scan|deploy → environmentVariables JSON
  case "$1" in
    build)  jq -nc --arg e "$ECR_URI" --arg r "$(mirror)" '[{name:"ECR_URI",value:$e},{name:"REGISTRY",value:$r}]' ;;
    scan)   jq -nc --arg e "$ECR_URI" '[{name:"ECR_URI",value:$e},{name:"GATE_SEVERITY",value:"CRITICAL"},{name:"GATE_MAX",value:"0"}]' ;;
    deploy) jq -nc --arg e "$ECR_URI" --arg g "${GITHUB_REPO:-$(fork_repo)}" --arg b "${GITOPS_BRANCH:-$(fork_branch)}" \
              '[{name:"ECR_URI",value:$e},{name:"GITHUB_REPO",value:$g},{name:"GITOPS_BRANCH",value:$b},{name:"GITHUB_TOKEN",value:"opslab/github-token",type:"SECRETS_MANAGER"}]' ;;
  esac
}
project_json() {  # $1=build|scan|deploy → create-project 입력 JSON
  local n=$SID-image-$1 priv=false; [ "$1" = build ] && priv=true   # 도커 빌드는 특권 모드가 필요하다
  jq -nc --arg n "$n" --arg role "$IMAGE_BUILD_ROLE_ARN" --arg spec "pipeline/buildspec-$1.yml" --argjson env "$(project_env "$1")" --argjson p $priv --arg sid "$SID" '{
    name:$n, serviceRole:$role, timeoutInMinutes:20,
    source:{type:"CODEPIPELINE", buildspec:$spec}, artifacts:{type:"CODEPIPELINE"},
    environment:{type:"LINUX_CONTAINER", image:"aws/codebuild/amazonlinux-x86_64-standard:5.0", computeType:"BUILD_GENERAL1_SMALL", privilegedMode:$p, environmentVariables:$env},
    logsConfig:{cloudWatchLogs:{status:"ENABLED"}},
    tags:[{key:"Course",value:"opslab"},{key:"Module",value:"image"},{key:"Owner",value:$sid}]}'
}
project_exists() { [ "$(aws codebuild batch-get-projects --names "$1" --query 'length(projects)' --output text 2>/dev/null)" = 1 ]; }
projects_create() { local p; for p in build scan deploy; do project_exists "$SID-image-$p" || aws codebuild create-project --cli-input-json "$(project_json $p)" >/dev/null || return 1; done; }
project_envget() { aws codebuild batch-get-projects --names "$1" --query 'projects[0].environment' --output json; }   # 원복용
project_envset() {  # $1=프로젝트 $2=변수 $3=값 [$4=유형(PLAINTEXT|SECRETS_MANAGER)] — 환경변수 하나만 바꾼다
  local e; e=$(project_envget "$1" | jq -c --arg k "$2" --arg v "$3" --arg t "${4:-PLAINTEXT}" '.environmentVariables |= map(if .name==$k then {name:$k,value:$v,type:$t} else . end)')
  aws codebuild update-project --name "$1" --environment "$e" >/dev/null
}

# ── 4) 파이프라인 — 소스(내 Fork 오늘 브랜치, app/·pipeline/ 변경만 깨움) → 빌드 → 스캔 게이트 → 매니페스트 반영
pipeline_json() {
  sed -e "s#__SID__#$SID#g" -e "s#__ROLE__#$IMAGE_PIPELINE_ROLE_ARN#g" -e "s#__BUCKET__#$IMAGE_BUCKET#g" -e "s#__CONN__#$(conn_arn)#g" \
      -e "s#__REPO__#${GITHUB_REPO:-$(fork_repo)}#g" -e "s#__BRANCH__#${GITOPS_BRANCH:-$(fork_branch)}#g" "$IM/pipeline.tpl.json"
}
pipe_exists() { aws codepipeline get-pipeline --name "$PIPE" >/dev/null 2>&1; }
pipe_last() { aws codepipeline list-pipeline-executions --pipeline-name "$PIPE" --max-items 1 --query 'pipelineExecutionSummaries[0].[pipelineExecutionId,status]' --output text 2>/dev/null | head -1; }
pipe_status() { aws codepipeline get-pipeline-execution --pipeline-name "$PIPE" --pipeline-execution-id "$1" --query pipelineExecution.status --output text 2>/dev/null; }
pipe_start() { aws codepipeline start-pipeline-execution --name "$PIPE" --query pipelineExecutionId --output text; }
pipe_wait() {  # $1=실행 ID [$2=초] → 끝난 상태(Succeeded·Failed·Superseded·Stopped)
  local s i; for i in $(seq 1 $(( ${2:-1200} / 10 ))); do s=$(pipe_status "$1"); case "$s" in InProgress|Stopping|"") sleep 10 ;; *) echo "$s"; return 0 ;; esac; done; pipe_status "$1"
}
pipe_settle() {  # [$1=초] — 진행 중인 실행이 하나도 없을 때까지 기다린 뒤 가장 최근 실행의 상태를 출력
  local i; for i in $(seq 1 $(( ${1:-1500} / 10 ))); do
    [ "$(aws codepipeline list-pipeline-executions --pipeline-name "$PIPE" --max-items 5 --query 'length(pipelineExecutionSummaries[?status==`InProgress` || status==`Stopping`])' --output text 2>/dev/null)" = 0 ] && break; sleep 10; done
  pipe_last | awk '{print $2}'
}
pipe_failed() {  # $1=실행 ID → 실패한 단계·액션과 요약
  aws codepipeline list-action-executions --pipeline-name "$PIPE" --filter pipelineExecutionId="$1" \
    --query 'actionExecutionDetails[?status==`Failed`].[stageName,actionName,output.executionResult.externalExecutionSummary]' --output text 2>/dev/null
}

# ── 상태 읽기
git_release() { gh_get "$(fork_repo)" "$(fork_branch)" "$VALUES" | sed -n "s/^release$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\}.*/\1/p"; }   # $1=Repository|Tag → Git 에 적힌 릴리스 이미지
running_image() { kubectl -n "$APP_NS" get deploy opslab-app -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].image}' 2>/dev/null; }
latest_src() {  # 오늘 브랜치에서 app/ 또는 pipeline/ 을 바꾼 가장 최근 커밋 SHA(파이프라인을 깨우는 커밋)
  local r b a p; r=$(fork_repo); b=$(fork_branch)
  a=$(gh_api GET "/repos/$r/commits?sha=$b&path=app&per_page=1" | jq -r '.[0].sha // empty')
  p=$(gh_api GET "/repos/$r/commits?sha=$b&path=pipeline&per_page=1" | jq -r '.[0].sha // empty')
  [ -z "$p" ] && { echo "$a"; return; }; [ -z "$a" ] && { echo "$p"; return; }
  [ "$(gh_api GET "/repos/$r/compare/$a...$p" | jq -r .status)" = behind ] && echo "$a" || echo "$p"
}
contains() {  # $1=커밋 $2=이미지 태그(짧은 SHA) → 태그 커밋이 $1 을 포함하면(같거나 뒤) 성공
  local s; s=$(gh_api GET "/repos/$(fork_repo)/compare/$1...$2" | jq -r '.status // empty'); [ "$s" = ahead ] || [ "$s" = identical ]
}
scan_counts() { aws ecr describe-image-scan-findings --repository-name "$REPO_NAME" --image-id imageTag="$1" --query imageScanFindings.findingSeverityCounts --output json 2>/dev/null; }
deploy_wait() {  # [$1=초] — Git 의 릴리스 이미지가 운영 앱에 반영되고(파드 교체 끝) Argo CD 앱이 모두 Synced·Healthy 가 될 때까지
  local t=${1:-420} want i; for i in $(seq 1 $((t / 10))); do
    want="$(git_release Repository):$(git_release Tag)"
    if [ "$(running_image)" = "$want" ] && kubectl -n "$APP_NS" rollout status deploy opslab-app --timeout=5s >/dev/null 2>&1 \
       && apps_wait 10; then return 0; fi
    [ $((i % 3)) -eq 0 ] && app_refresh $APPS; sleep 10
  done; return 1
}
conn_wait() {  # [$1=초] — GitHub 연결이 AVAILABLE 이 될 때까지(수강생이 콘솔에서 승인)
  local i s; for i in $(seq 1 $(( ${1:-600} / 10 ))); do s=$(conn_status); [ "$s" = AVAILABLE ] && return 0; sleep 10; done; return 1
}
