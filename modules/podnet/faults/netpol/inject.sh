#!/bin/bash
# podnet-5 netpol — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: app 네임스페이스의 NetworkPolicy
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) # "보안 강화"로 기본 거부 정책 추가 — 허용 규칙 없이 모든 들어오는 통신을 막는다(ALB → 파드도 막힘)
     kubectl apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: $NS, labels: { course: opslab } }
spec: { podSelector: {}, policyTypes: [Ingress] }
YAML
     ;;
  2) # DB 허용 정책의 출발지 라벨이 앱 라벨과 다르다 → 앱이 DB·캐시에 접속하지 못한다
     kubectl -n "$NS" patch networkpolicy db-allow-app --type json \
       -p '[{"op":"replace","path":"/spec/ingress/0/from/0/podSelector/matchLabels/app.kubernetes.io~1name","value":"opslab-api"}]' >/dev/null ;;
  3) # 앱 파드에서 나가는 통신을 DNS·HTTP 만 허용 — DB(5432) 가 빠졌다
     kubectl apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: app-egress, namespace: $NS, labels: { course: opslab } }
spec:
  podSelector: { matchLabels: { app.kubernetes.io/name: opslab-app } }
  policyTypes: [Egress]
  egress:
    - ports: [{ protocol: UDP, port: 53 }, { protocol: TCP, port: 53 }, { protocol: TCP, port: 6379 }, { protocol: TCP, port: 443 }]
YAML
     ;;
esac
record $V
