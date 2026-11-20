#!/bin/bash
# podnet-4 coredns — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: kube-system/coredns(관리형 애드온) Deployment·ConfigMap(변형 ①②), app 네임스페이스 NetworkPolicy(변형 ③)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3)
case $V in
  1) save replicas "$(kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}')"
     kubectl -n kube-system scale deploy coredns --replicas=0 >/dev/null ;;                       # 전화번호부 0개
  2) # Corefile 오타("forward" → "forwrd") 뒤 재시작 → 설정을 읽지 못해 CrashLoopBackOff
     save corefile "$(kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | base64 -w0)"
     kubectl -n kube-system get cm coredns -o json | jq '.data.Corefile |= sub("forward \\."; "forwrd .")' | kubectl replace -f - >/dev/null
     kubectl -n kube-system rollout restart deploy coredns >/dev/null ;;
  3) # app 네임스페이스에서 나가는 통신을 "DB 포트만" 허용하는 정책 — DNS(53) 가 빠졌다
     kubectl apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: egress-db-only, namespace: $NS, labels: { course: opslab } }
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - ports: [{ protocol: TCP, port: 5432 }, { protocol: TCP, port: 6379 }, { protocol: TCP, port: 8080 }]
YAML
     ;;
esac
sleep 10; kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null   # 새로 뜨는 파드는 DB 주소를 찾지 못한다
record $V
