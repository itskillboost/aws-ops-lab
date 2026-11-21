#!/bin/bash
# gitops-2 drift — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 내 Fork 오늘 브랜치의 운영 앱 정의(gitops/apps/templates/prod.yaml)·운영 값(gitops/envs/prod/values.yaml), app/opslab-app Deployment
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); base_save
case $V in
  1) # 자동 치유(selfHeal)를 끈 커밋 → 그 뒤 누군가 디버깅하다 kubectl 로 바꾼 값(오류율 50%)이 그대로 남았다
     commit "$PA" "운영 앱: 디버깅하는 동안 자동 치유 끔" 's/selfHeal: true/selfHeal: false/'
     kick; wait_spec '.spec.syncPolicy.automated.selfHeal != true'
     wait_prod_rev 180; sleep 30   # 새 커밋으로 한 번 자동 동기화한 뒤에 손을 대야 남는다(커밋이 바뀌면 자동 동기화가 수동 변경을 덮는다)
     kubectl -n "$NS" set env deploy/"$DEP" APP_ERROR_RATE=0.5 >/dev/null ;;
  2) # 운영 값에 시험용 오류 플래그가 커밋됐다 → 당직자가 kubectl 로 급히 껐지만 자동 치유가 Git 값으로 되돌린다
     commit "$PV" "운영 값: 오류 처리 시험 플래그 추가" 's/^  APP_VERSION: v1$/  APP_VERSION: v1\n  APP_ERROR_RATE: "0.5"   # 오류 처리 시험/'
     kick; wait_prod_rev 180; sleep 45
     kubectl -n "$NS" set env deploy/"$DEP" APP_ERROR_RATE=0 >/dev/null   # 당직자의 긴급 조치(곧 되돌려진다)
     ;;
  3) # "행사 대비 최소 3대" 커밋 + 운영 앱 정의에서 ignoreDifferences 가 빠졌다 → HPA 는 3, Argo CD 는 Git 의 2 로 서로 되돌린다
     commit "$PA" "운영 앱 정의 정리" '/^  ignoreDifferences:/,$d'
     commit "$PV" "행사 대비 최소 파드 3개" 's/^  minReplicas: 2$/  minReplicas: 3/'
     kick; wait_spec '(.spec.ignoreDifferences // []) | length == 0' ;;
esac
record $V
