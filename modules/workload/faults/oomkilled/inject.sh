#!/bin/bash
# workload-3 oomkilled — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment, (변형 ③) app 네임스페이스의 LimitRange app-defaults
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # 메모리 요청·상한 축소 ("자원 절약" 변경). 요청 ≤ 상한 규칙 때문에 둘 다 줄인다
     patch --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"64Mi"},
                            {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"64Mi"}]' ;;
  2) kubectl -n "$NS" set env deploy/"$DEP" -c app APP_MEM_MB=400 >/dev/null ;;                                                     # 앱이 메모리를 더 쓰는 새 설정
  3) kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: LimitRange
metadata: { name: app-defaults, labels: { course: opslab } }
spec:
  limits:
    - type: Container
      default: { memory: 64Mi }
      defaultRequest: { memory: 32Mi }
YAML
     # 자원 설정(resources)을 "제한을 풀어 준다"며 통째로 지운 변경 — 네임스페이스 기본값(LimitRange)이 대신 들어간다
     patch --type json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/resources"}]' ;;
esac
record $V
