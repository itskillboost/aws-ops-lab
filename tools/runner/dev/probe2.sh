source common/eks.sh; kube_login; export LAB=probe SID; source modules/cluster/node.sh
PG=$(kubectl -n app get pod postgres-0 -o jsonpath='{.spec.nodeName}')
N=$(kubectl get nodes -o name | cut -d/ -f2 | grep -vx "$PG" | head -1); echo "TARGET $N"
on_node $N "grep -o '\"podPidsLimit\": *[-0-9]*' /etc/kubernetes/kubelet/config.json; cat /etc/kubernetes/kubelet/config.json.d/40-nodeadm.conf | head -c 800; echo; cat /sys/fs/cgroup/kubepods.slice/pids.max; ulimit -u"
echo "=== pid test pod"
kubectl run pidtest -n app --image=$(img_repo app):$(img_tag app) --restart=Never --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$N\"}}}" --command -- sh -c 'id; ulimit -u; cat /sys/fs/cgroup/pids.max; i=0; while [ $i -lt 3000 ]; do sleep 600 & i=$((i+1)); done; echo spawned $i; sleep 5; ls /proc | grep -c "^[0-9]"; sleep 30'
sleep 40; kubectl -n app logs pidtest | tail -8; kubectl -n app get pod pidtest; kubectl -n app delete pod pidtest --now
echo "=== memory 500Mi threshold"
on_node $N "echo '{\"apiVersion\":\"kubelet.config.k8s.io/v1beta1\",\"kind\":\"KubeletConfiguration\",\"evictionHard\":{\"memory.available\":\"500Mi\",\"nodefs.available\":\"10%\",\"nodefs.inodesFree\":\"5%\",\"imagefs.available\":\"15%\",\"pid.available\":\"25%\"}}' > /etc/kubernetes/kubelet/config.json.d/90-opslab.conf; echo 8192 > /proc/sys/kernel/pid_max; systemctl restart kubelet; sleep 5; systemctl is-active kubelet"
sleep 20
LAB=cluster-2 VARIANT=2 bash modules/cluster/faults/node-pressure/inject.sh; echo "inject rc=$?"
for i in $(seq 1 15); do sleep 20; echo "--- t+$((i*20))s $(kubectl get node $N -o jsonpath='{range .status.conditions[?(@.type=="MemoryPressure")]}{.type}={.status}{end}') $(kubectl -n app get pods -l app.kubernetes.io/name=opslab-batch --no-headers 2>/dev/null | head -2 | tr '\n' ' ')"; done
kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'memory|evict|oom' | tail -8 | cut -c1-200
LAB=cluster-2 bash modules/cluster/faults/node-pressure/rollback.sh
