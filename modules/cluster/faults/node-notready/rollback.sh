#!/bin/bash
# cluster-1 node-notready — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 수강생이 일부를 고친 상태여도 안전하다: 설정 백업이 있으면 되돌리고, 런타임 mask 를 풀고, 두 서비스를 켠다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
N=$(load node); [ -n "$N" ] && [ "$N" != None ] || N=$(target_node)
on_node "$N" "[ -f /var/lib/opslab-kubelet-config.bak ] && cp /var/lib/opslab-kubelet-config.bak /etc/kubernetes/kubelet/config.json && rm -f /var/lib/opslab-kubelet-config.bak
  systemctl unmask --runtime containerd 2>/dev/null; systemctl start containerd; systemctl reset-failed kubelet; systemctl start kubelet; sleep 5
  systemctl is-active containerd kubelet" | sed 's/^/  /'
kubectl wait --for=condition=Ready node/"$N" --timeout=180s >/dev/null && echo "  노드 $N Ready" || echo "  ⚠️ 노드 $N 가 아직 Ready 가 아닙니다"
