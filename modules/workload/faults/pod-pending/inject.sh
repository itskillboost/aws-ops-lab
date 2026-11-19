#!/bin/bash
# workload-1 pod-pending — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment, (변형 ③) 노드 taint opslab/maintenance
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # 노드보다 큰 CPU 요청 (상한도 함께 올려야 쿠버네티스가 받아들인다: requests ≤ limits)
     patch --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"8"},
                            {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"8"}]' ;;
  2) patch --type merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"disktype":"ssd"}}}}}' ;;                                  # 없는 라벨의 노드만 고르게
  3) kubectl taint nodes --all opslab/maintenance=true:NoSchedule --overwrite >/dev/null                                           # 모든 노드 "출입 제한"
     kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null ;;
esac
record $V
