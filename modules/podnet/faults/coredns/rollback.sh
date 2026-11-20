#!/bin/bash
# podnet-4 coredns — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
C=$(load corefile); if [ -n "$C" ] && [ "$C" != None ]; then
  kubectl -n kube-system get cm coredns -o json | jq --arg c "$(base64 -d <<<"$C")" '.data.Corefile=$c' | kubectl replace -f - >/dev/null && echo "  Corefile 복원"
  aws ssm delete-parameter --name "$STATE/corefile" >/dev/null 2>&1; kubectl -n kube-system rollout restart deploy coredns >/dev/null
fi
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep -q 'forwrd' && {
  kubectl -n kube-system get cm coredns -o json | jq '.data.Corefile |= sub("forwrd \\."; "forward .")' | kubectl replace -f - >/dev/null; kubectl -n kube-system rollout restart deploy coredns >/dev/null; echo "  Corefile 오타 수정"; }
R=$(load replicas); [ -z "$R" ] || [ "$R" = None ] && R=2
[ "$(kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}')" -ge 1 ] || { kubectl -n kube-system scale deploy coredns --replicas="$R" >/dev/null; echo "  CoreDNS $R 개로 복원"; }
kubectl -n "$NS" delete networkpolicy egress-db-only --ignore-not-found >/dev/null && echo "  NetworkPolicy egress-db-only 삭제"
kubectl -n kube-system rollout status deploy coredns --timeout=3m >/dev/null
kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null; kubectl -n "$NS" rollout status deploy "$DEP" --timeout=5m >/dev/null && echo "  앱 배포 완료"
kubectl -n "$NS" rollout restart deploy opslab-load >/dev/null 2>&1; true
