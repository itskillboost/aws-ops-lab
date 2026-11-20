source common/eks.sh; kube_login; export LAB=probe; source modules/cluster/node.sh
PG=$(kubectl -n app get pod postgres-0 -o jsonpath='{.spec.nodeName}')
N=$(kubectl get nodes -o name | cut -d/ -f2 | grep -vx "$PG" | head -1); echo "TARGET $N (pg $PG)"
echo "=== facts"; on_node $N "systemctl show kubelet -p Requires -p Wants -p BindsTo; ls /etc/kubernetes/kubelet/; grep -o '\"maxPods\": *[0-9]*' /etc/kubernetes/kubelet/config.json; cat /proc/sys/kernel/pid_max; ps -eL --no-headers | wc -l; df -h / | tail -1; free -m | head -2"
echo "=== V2 containerd stop+mask"
on_node $N "systemctl mask --runtime containerd && systemctl stop containerd; sleep 5; systemctl is-active kubelet containerd"
sleep 70; kubectl get node $N; kubectl get node $N -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason} {.message}{"\n"}{end}' | grep -E "^Ready"
on_node $N "journalctl -u kubelet --since -2min --no-pager | tail -4 | cut -c1-250"
on_node $N "systemctl unmask --runtime containerd; systemctl start containerd; systemctl start kubelet; sleep 3; systemctl is-active kubelet containerd"
sleep 45; kubectl get node $N
echo "=== V3 config corrupt"
on_node $N "cp -n /etc/kubernetes/kubelet/config.json /var/lib/opslab-kubelet-config.bak; sed -i 's/\"maxPods\": *\([0-9]*\)/\"maxPods\": \"\1 pods\"/' /etc/kubernetes/kubelet/config.json; grep -o '\"maxPods\": *[^,]*' /etc/kubernetes/kubelet/config.json; systemctl restart kubelet; sleep 15; systemctl is-active kubelet; systemctl show kubelet -p NRestarts; journalctl -u kubelet -n 30 --no-pager | grep -iE 'error|fail' | tail -3 | cut -c1-300"
sleep 50; kubectl get node $N
on_node $N "cp /var/lib/opslab-kubelet-config.bak /etc/kubernetes/kubelet/config.json && rm -f /var/lib/opslab-kubelet-config.bak; systemctl reset-failed kubelet; systemctl restart kubelet; sleep 3; systemctl is-active kubelet"
sleep 40; kubectl get node $N
echo "=== PID setup (node-level, simulating LT user data)"
on_node $N "echo 8192 > /proc/sys/kernel/pid_max; ls /etc/kubernetes/kubelet/config.json.d/ 2>&1; mkdir -p /etc/kubernetes/kubelet/config.json.d; echo '{\"apiVersion\":\"kubelet.config.k8s.io/v1beta1\",\"kind\":\"KubeletConfiguration\",\"evictionHard\":{\"memory.available\":\"100Mi\",\"nodefs.available\":\"10%\",\"nodefs.inodesFree\":\"5%\",\"imagefs.available\":\"15%\",\"pid.available\":\"25%\"}}' > /etc/kubernetes/kubelet/config.json.d/90-opslab.conf; systemctl restart kubelet; sleep 5; systemctl is-active kubelet; ps -eL --no-headers | wc -l"
sleep 30
echo "=== V3 PID batch"
export SID; LAB=cluster-2 VARIANT=3 bash modules/cluster/faults/node-pressure/inject.sh; echo "inject rc=$?"
for i in 1 2 3 4 5 6 7 8 9; do sleep 20; echo "--- t+$((i*20))s"; kubectl get node $N -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'; kubectl -n app get pods -l app.kubernetes.io/name=opslab-batch --no-headers 2>/dev/null | head -3; done
kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'pid|evict|pressure' | tail -6 | cut -c1-220
LAB=cluster-2 bash modules/cluster/faults/node-pressure/rollback.sh
echo "=== V2 memory batch"
LAB=cluster-2 VARIANT=2 bash modules/cluster/faults/node-pressure/inject.sh; echo "inject rc=$?"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 20; echo "--- t+$((i*20))s"; kubectl get node $N -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'; kubectl -n app get pods -l app.kubernetes.io/name=opslab-batch --no-headers 2>/dev/null | head -3; done
kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'memory|evict|pressure|oom' | tail -8 | cut -c1-220
LAB=cluster-2 bash modules/cluster/faults/node-pressure/rollback.sh
echo "=== V1 disk"
LAB=cluster-2 VARIANT=1 bash modules/cluster/faults/node-pressure/inject.sh; echo "inject rc=$?"
for i in 1 2 3 4 5 6; do sleep 20; echo "--- t+$((i*20))s"; kubectl get node $N -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'; done
kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'disk|evict|pressure|garbage' | tail -8 | cut -c1-220
LAB=cluster-2 bash modules/cluster/faults/node-pressure/rollback.sh
echo "=== final"; kubectl get nodes; bash modules/cluster/baseline/verify.sh | tail -12
