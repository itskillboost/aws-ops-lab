#!/bin/bash
# workload-2 crashloop — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Deployment 의 app 컨테이너 설정만 변경
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) kubectl -n "$NS" set env deploy/"$DEP" -c app DB_HOST=postgres-primary >/dev/null ;;                       # 없는 DB 주소
  2) patch --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["gunicorn","--preload","-b","0.0.0.0:8080","app:application"]}]' ;;   # 잘못된 실행 명령
  3) patch --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/securityContext/readOnlyRootFilesystem","value":true}]' ;;   # 읽기 전용 루트 파일시스템
esac
record $V
