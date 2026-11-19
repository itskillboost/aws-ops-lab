#!/bin/bash
# workload-4 probe-restart — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment 의 probe·환경변수만 변경
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
C=/spec/template/spec/containers/0
V=$(pick_variant 3)
case $V in
  1) patch --type json -p "[{\"op\":\"replace\",\"path\":\"$C/livenessProbe/httpGet/path\",\"value\":\"/healthz\"}]" ;;            # 없는 경로
  2) patch --type json -p "[{\"op\":\"replace\",\"path\":\"$C/livenessProbe/timeoutSeconds\",\"value\":1},
                           {\"op\":\"replace\",\"path\":\"$C/livenessProbe/failureThreshold\",\"value\":1},
                           {\"op\":\"add\",\"path\":\"$C/env/-\",\"value\":{\"name\":\"APP_HEALTH_DELAY\",\"value\":\"1.5\"}}]" ;;  # 짧은 timeout + 느린 응답
  3) patch --type json -p "[{\"op\":\"remove\",\"path\":\"$C/startupProbe\"},
                           {\"op\":\"add\",\"path\":\"$C/env/-\",\"value\":{\"name\":\"APP_START_DELAY\",\"value\":\"45\"}}]" ;;   # 느린 시작 + startup probe 없음
esac
record $V
