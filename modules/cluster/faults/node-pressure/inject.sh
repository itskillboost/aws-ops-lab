#!/bin/bash
# cluster-2 node-pressure — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 노드 한 대(PostgreSQL 이 없는 노드)의 디스크(파일 하나), app 네임스페이스의 Deployment 하나(opslab-batch)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); N=$(target_node); save node "$N"
batch() {  # $1=컨테이너 명령(JSON 배열) [$2=파드 수] — 자원 제한(requests·limits) 없이 그 노드에만 도는 "야간 배치" 파드
  kubectl apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: opslab-batch, namespace: $NS, labels: { app.kubernetes.io/name: opslab-batch, course: opslab } }
spec:
  replicas: ${2:-1}
  selector: { matchLabels: { app.kubernetes.io/name: opslab-batch } }
  template:
    metadata: { labels: { app.kubernetes.io/name: opslab-batch } }
    spec:
      nodeSelector: { kubernetes.io/hostname: "$N" }
      terminationGracePeriodSeconds: 2
      containers:
        - name: batch
          image: $(img_repo app):$(img_tag app)
          command: $1
YAML
}
case $V in
  1) # 디스크 채우기: 루트 디스크 남은 공간을 5% 정도만 남기고 덤프 파일 하나로 채운다 → DiskPressure → 파드 축출
     on_node "$N" 'f=/var/log/app-core.dump; t=$(df --output=size -B1 / | tail -1); a=$(df --output=avail -B1 / | tail -1)
       fallocate -l $(( a - t*5/100 )) $f && df -h /' >/dev/null ;;
  2) # 메모리: 제한 없는 배치 파드가 노드 메모리를 거의 다 쓸 때까지 조금씩 늘린다 → MemoryPressure → 축출 → 다시 생성 반복
     M=$(on_node "$N" "awk '/MemAvailable/{print int(\$2/1024)}' /proc/meminfo" | tr -dc 0-9)
     batch "[\"python3\",\"-c\",\"import time\\na=[]\\nwhile len(a)*32<$((M-150)): a.append(bytearray(32*2**20)); time.sleep(1)\\nwhile True: time.sleep(60)\"]" ;;
  3) # 프로세스: 배치 파드 6개가 각자 끝나지 않는 하위 프로세스를 1100개씩 만든다 → 노드 프로세스 수가 한도(8192)의 75% 를 넘어 PIDPressure
     #    (파드 하나는 1228개를 넘게 만들 수 없다 — 파드별 PID 한도. 그래서 여러 개로 나눈다)
     batch '["sh","-c","i=0; while [ $i -lt 1100 ]; do sleep 86400 & i=$((i+1)); done; wait"]' 6 ;;
esac
record $V
