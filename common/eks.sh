#!/bin/bash
# EKS 과정 공통 함수 — start.sh·check.sh·review.sh·headlamp.sh·장애 스크립트가 source 한다.
# 과정 파일은 COURSE 환경변수(~/opslab-env.sh 의 export COURSE=skons-eks)로 고른다.
EKS_ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
COURSE_FILE="$EKS_ROOT/courses/${COURSE:-skons}.yaml"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
export PATH="$HOME/bin:$PATH"
CLUSTER="${SID:-s00}-cluster-eks"
APP_NS=app                                    # 샘플 앱·DB 네임스페이스 (라벨 course=opslab)

cval() {  # 과정 파일 최상위 값: cval eks_version
  sed -n "s/^$1: *//p" "$COURSE_FILE" | sed 's/ *#.*//; s/^"//; s/"$//' | head -1
}
img() {   # 이미지 주소: 과정 파일 images.<키> 를 미러 레지스트리 주소로 바꾼다 (registry 가 TBD 면 원래 주소)
  local src reg; src=$(sed -n '/^images:/,/^[a-z]/p' "$COURSE_FILE" | sed -n "s/^  $1: *//p" | sed 's/ *#.*//')
  reg=$(cval registry)
  if [ -n "$reg" ] && [ "$reg" != TBD ]; then echo "$reg/${src##*/}"; return; fi
  case "$src" in
    *.*/*) echo "$src" ;;                                   # registry.k8s.io/... ghcr.io/...
    library/*) echo "public.ecr.aws/docker/$src" ;;          # 도커 공식 이미지는 ECR Public 사본
    opslab-app*) echo "❌ 과정 파일 registry 가 TBD 입니다(앱 이미지는 미러에만 있음)" >&2; return 1 ;;
    *) echo "docker.io/$src" ;;
  esac
}
img_repo() { local i; i=$(img "$1") || return 1; echo "${i%:*}"; }
img_tag()  { local i; i=$(img "$1") || return 1; echo "${i##*:}"; }

kube_login() {  # kubeconfig(접속 카드) 갱신 — 클러스터를 새로 만들면 다시 받아야 한다
  aws eks update-kubeconfig --name "$CLUSTER" --alias "$SID" >/dev/null 2>&1
}
have_cluster() { aws eks describe-cluster --name "$CLUSTER" --query cluster.status --output text 2>/dev/null | grep -q ACTIVE; }
