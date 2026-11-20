#!/bin/bash
# cluster-1 node-notready — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 노드 한 대(PostgreSQL 이 없는 노드)의 kubelet·containerd 서비스와 kubelet 설정 파일
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); N=$(target_node); save node "$N"
case $V in
  1) on_node "$N" "systemctl stop kubelet" >/dev/null ;;                                   # 현장 반장 퇴근
  2) on_node "$N" "systemctl mask --runtime containerd && systemctl stop containerd" >/dev/null ;;   # 작업자 퇴근(다시 못 켜게 runtime mask)
  3) on_node "$N" "cp -n /etc/kubernetes/kubelet/config.json /var/lib/opslab-kubelet-config.bak
       sed -i 's/\"maxPods\": *\([0-9]*\)/\"maxPods\": \"\1 pods\"/' /etc/kubernetes/kubelet/config.json
       systemctl restart kubelet" >/dev/null ;;                                             # 설정 파일 손상 후 재시작 → 재시작 루프
esac
record $V
