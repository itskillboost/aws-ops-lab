#!/bin/bash
# podnet-1 ip-exhaust — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 실습 태그를 붙인 ENI(변형 ①), kube-system/aws-node 환경변수 MAX_ENI(변형 ②), app/opslab-batch Deployment
# 공통: "야간 대량 처리" 배치 Deployment(opslab-batch)를 노드에 남은 IP(웜 풀)보다 많이 늘린다 → IP 를 못 받은 파드가 ContainerCreating 에 멈춘다
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2)
# 노드에 더 올릴 수 있는 파드 수(maxPods − 지금 파드 수, 호스트 네트워크 파드 제외 아님 — 스케줄러 기준)의 합에서 2를 뺀 만큼 배치를 띄운다
slots=0
for n in $(kubectl get nodes -o name | cut -d/ -f2); do
  m=$(kubectl get node "$n" -o jsonpath='{.status.allocatable.pods}')
  u=$(kubectl get pods -A --field-selector spec.nodeName="$n",status.phase!=Succeeded,status.phase!=Failed --no-headers | wc -l)
  slots=$((slots + m - u))
done
REP=$((slots - 2)); [ "$REP" -gt 40 ] && REP=40
case $V in
  1) # 앱 서브넷 2개의 남은 IP 를 "다른 팀 ENI" 로 거의 다 써 버린다(각 서브넷 2개만 남김)
     for sub in $(aws ec2 describe-subnets --filters Name=tag:Owner,Values="$SID" "Name=tag:Name,Values=$SID-base-app-*" --query 'Subnets[].SubnetId' --output text); do
       free=$(aws ec2 describe-subnets --subnet-ids "$sub" --query 'Subnets[0].AvailableIpAddressCount' --output text)
       while [ "$free" -gt 3 ]; do
         c=$((free - 3)); [ "$c" -gt 49 ] && c=49
         aws ec2 create-network-interface --subnet-id "$sub" --description "opslab legacy-batch $SID" --secondary-private-ip-address-count "$c" \
           --tag-specifications "ResourceType=network-interface,Tags=[{Key=Course,Value=opslab},{Key=Module,Value=podnet},{Key=Owner,Value=$SID},{Key=Name,Value=$SID-legacy-batch}]" >/dev/null
         free=$(aws ec2 describe-subnets --subnet-ids "$sub" --query 'Subnets[0].AvailableIpAddressCount' --output text)
       done
     done ;;
  2) # aws-node(VPC CNI)가 노드에 붙일 수 있는 ENI 를 1개로 제한 → 노드당 파드 IP 가 크게 줄어든다
     kubectl -n kube-system set env ds/aws-node MAX_ENI=1 >/dev/null
     kubectl -n kube-system rollout status ds/aws-node --timeout=5m >/dev/null ;;
esac
kubectl -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: opslab-batch, namespace: $NS, labels: { app.kubernetes.io/name: opslab-batch, course: opslab } }
spec:
  replicas: $REP
  selector: { matchLabels: { app.kubernetes.io/name: opslab-batch } }
  template:
    metadata: { labels: { app.kubernetes.io/name: opslab-batch, course: opslab } }
    spec:
      containers:
        - name: batch
          image: $(img busybox)
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 5m, memory: 8Mi }, limits: { memory: 16Mi } }
YAML
sleep 20; kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null   # 같은 시각 배포된 새 버전도 IP 를 받지 못한다
record $V
