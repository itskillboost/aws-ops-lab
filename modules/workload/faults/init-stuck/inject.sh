#!/bin/bash
# workload-6 init-stuck — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment 의 init 컨테이너(wait-db)만 변경
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
I=/spec/template/spec/initContainers/0
V=$(pick_variant 3)
case $V in
  1) kubectl -n "$NS" set env deploy/"$DEP" -c wait-db DB_HOST=postgresql >/dev/null ;;                                    # 대기 대상 서비스 이름 오타
  2) patch --type json -p "[{\"op\":\"replace\",\"path\":\"$I/command\",\"value\":[\"sh\",\"-c\",\"until [ -f /tmp/db-ready ]; do echo waiting for database; sleep 2; done\"]}]" ;;   # 끝나지 않는 대기 명령
  3) IMG=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.initContainers[0].image}')
     kubectl -n "$NS" set image deploy/"$DEP" wait-db="${IMG%:*}:1.73" >/dev/null ;;                                         # init 이미지 풀 실패
esac
record $V
