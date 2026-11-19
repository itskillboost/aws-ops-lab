#!/bin/bash
# 강사용 이미지 미러링 — 과정 파일 images: 의 외부 이미지를 강사 ECR Public 에 같은 태그로 복사하고, 샘플 앱 이미지를 빌드해 올린다.
#   COURSE=skons-eks bash tools/mirror-images.sh        # docker 가 있는 곳(CodeBuild 특권 모드, Cloud9, 강사 PC)에서 실행
# 끝나면 출력되는 registry 값을 과정 파일 registry: 에 적는다. 저장소 이름은 opslab/<이미지 이름> 이다(예 opslab/headlamp).
# ECR Public 은 us-east-1 에서만 관리한다. 받기(pull)는 어느 리전에서나 익명으로 된다.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
COURSE_FILE="$ROOT/courses/${COURSE:?COURSE=<과정ID> 를 지정하세요}.yaml"
E="aws --region us-east-1 ecr-public"
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws >/dev/null
sed -n '/^images:/,/^[a-z]/p' "$COURSE_FILE" | sed -n 's/^  \([a-z-]*\): *\([^ #]*\).*/\1 \2/p' | while read -r key src; do
  name=${src##*/}; repo=opslab/${name%%:*}; tag=${name##*:}
  $E describe-repositories --repository-names "$repo" >/dev/null 2>&1 \
    || $E create-repository --repository-name "$repo" --catalog-data "description=Ops Lab mirror of $src" >/dev/null
  uri=$($E describe-repositories --repository-names "$repo" --query 'repositories[0].repositoryUri' --output text)
  if [ "$key" = app ]; then
    docker build -q -f "$ROOT/app/Dockerfile" -t "$uri:$tag" "$ROOT" >/dev/null
  else
    case "$src" in *.*/*) from=$src ;; library/*) from=public.ecr.aws/docker/$src ;; *) from=docker.io/$src ;; esac
    docker pull -q --platform linux/amd64 "$from" >/dev/null && docker tag "$from" "$uri:$tag"
  fi
  docker push -q "$uri:$tag" >/dev/null && echo "  ✅ $key  $src → $uri:$tag"
done
ALIAS=$($E describe-registries --query 'registries[0].aliases[0].name' --output text)
echo "과정 파일에 적을 값 →  registry: public.ecr.aws/$ALIAS/opslab"
