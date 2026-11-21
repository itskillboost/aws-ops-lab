#!/bin/bash
# gitops-5 env-values — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 내 Fork 오늘 브랜치의 운영 앱 정의(gitops/apps/templates/prod.yaml)·운영 값, 그 결과로 app 네임스페이스의 샘플 앱
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2); base_save
case $V in
  1) # 운영 앱이 개발 값(envs/dev)을 읽는다 — 운영 파드가 DB·캐시 없이(개발 설정으로) 뜬다 → /db·/cache 오류
     commit "$PA" "운영 앱 값 파일 정리" 's#envs/prod/values.yaml#envs/dev/values.yaml#' ;;
  2) # 값 파일 경로 오타(envs/prd) — Argo CD 가 매니페스트를 만들지 못해(ComparisonError) 릴리스 v2 가 반영되지 않는다
     release_v2
     commit "$PA" "값 파일 경로 정리" 's#envs/prod/values.yaml#envs/prd/values.yaml#' ;;
esac
kick
record $V
