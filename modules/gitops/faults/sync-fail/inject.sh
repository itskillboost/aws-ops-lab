#!/bin/bash
# gitops-3 sync-fail — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 내 Fork 오늘 브랜치의 운영 값(gitops/envs/prod/values.yaml), 그 결과로 app 네임스페이스의 샘플 앱 배포
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); base_save
case $V in
  1) # 적용 순서(sync-wave) 오류: 설정 v2(새 ConfigMap 이름)의 wave 가 1 — 앱(wave 0)이 먼저 새 설정을 찾다가 멈추고,
     #    Argo CD 는 앱이 건강해지기를 기다리느라 wave 1(설정)로 넘어가지 못한다
     commit "$PV" "설정 v2: 검색 기능 플래그(설정 이름에 버전을 붙여 교체)" \
       's/name: opslab-app-config-v1/name: opslab-app-config-v2/; s/^  wave: "-1"$/  wave: "1"/; s/^    APP_GREETING: hello$/    APP_GREETING: hello\n    APP_FEATURE_SEARCH: "on"/' ;;
  2) # PreSync 훅 실패: 릴리스 v2 커밋에 배포 전 점검 대상을 없는 서비스(postgres-ro)로 바꿨다 → 점검 Job 실패 → 배포 중단
     commit "$PV" "릴리스 v2: 배포 전 점검을 읽기 전용 DB 로" \
       's/^  APP_VERSION: v1$/  APP_VERSION: v2/; /^precheck:/,/^[a-z]/ s/^  enabled: true$/  enabled: true\n  host: postgres-ro/' ;;
  3) # 헬스 판정 Progressing 고착: 릴리스 v2 가 준비 확인(readiness) 경로를 없는 /ready 로 — 새 파드가 끝내 준비되지 않는다
     release_v2
     commit_append "$PV" "준비 확인(readiness) 경로를 /ready 로" $'probes:\n  readiness:\n    path: /ready' ;;
esac
kick
record $V
