#!/bin/bash
# podnet-2 svc-ingress — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app/opslab-app Service(변형 ①②), app/opslab-app Ingress(변형 ③)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # Service 셀렉터가 파드 라벨과 다르다(“새 이름표 규칙” 적용 실수) → Endpoints 가 비고 ALB 타깃이 0개
     kubectl -n "$NS" patch svc "$DEP" --type merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"opslab-api"}}}' >/dev/null ;;
  2) # Service 가 파드가 듣지 않는 포트(8081)로 보낸다 → 타깃은 있으나 건강검진 실패
     kubectl -n "$NS" patch svc "$DEP" --type json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8081}]' >/dev/null ;;
  3) # Ingress 의 백엔드 Service 이름 오타 → 정문 안내 데스크가 엉뚱한 번호로 안내
     kubectl -n "$NS" patch ingress "$DEP" --type json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"opslab-ap"}]' >/dev/null ;;
esac
record $V
