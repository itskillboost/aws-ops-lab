#!/bin/bash
# access-4 rbac — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app 네임스페이스의 Role dev(①)·RoleBinding dev(②), IAM 역할 <학번>-access-dev-role 의 접근 항목 그룹(③)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # Role 에서 파드 목록 보기(list) 동사가 빠짐 — "정리"하다 지웠다
     kubectl -n "$NS" patch role dev --type json -p '[{"op":"replace","path":"/rules/0/verbs","value":["get","watch"]}]' >/dev/null ;;
  2) # RoleBinding 의 대상 그룹 이름 오타(opslab-dev → opslab-devs) — 권한이 아무에게도 연결되지 않는다
     kubectl -n "$NS" patch rolebinding dev --type json -p '[{"op":"replace","path":"/subjects/0/name","value":"opslab-devs"}]' >/dev/null ;;
  3) # 접근 항목의 쿠버네티스 그룹이 다른 이름(opslab-developers) — 클러스터에는 들어오지만 RBAC 가 그 그룹을 모른다
     aws eks update-access-entry --cluster-name "$CLUSTER" --principal-arn "arn:aws:iam::$ACCT:role/$DEV_ROLE" --kubernetes-groups opslab-developers >/dev/null ;;
esac
record $V
