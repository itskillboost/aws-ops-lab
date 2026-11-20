source common/eks.sh; kube_login; export LAB=probe SID; source modules/cluster/node.sh
PG=$(kubectl -n app get pod postgres-0 -o jsonpath='{.spec.nodeName}')
N=$(kubectl get nodes -o name | cut -d/ -f2 | grep -vx "$PG" | head -1); echo "TARGET $N"
echo "=== PID v3 (6 pods)"
LAB=cluster-2 VARIANT=3 bash modules/cluster/faults/node-pressure/inject.sh; echo "inject rc=$?"
for i in $(seq 1 9); do sleep 20; echo "--- t+$((i*20))s $(kubectl get node $N -o jsonpath='{range .status.conditions[?(@.type=="PIDPressure")]}{.type}={.status}{end}') $(kubectl -n app get pods -l app.kubernetes.io/name=opslab-batch --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | tr '\n' ' ')"; done
on_node $N "ps -eL --no-headers | wc -l"
kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'pid|evict' | tail -5 | cut -c1-200
LAB=cluster-2 bash modules/cluster/faults/node-pressure/rollback.sh
echo "=== cluster-3 v1 access entry"
LAB=cluster-3 VARIANT=1 bash modules/cluster/faults/control-plane/inject.sh; echo "inject rc=$?"
sleep 60; kubectl get nodes; kubectl get node $N -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status} {.reason} {.message}{end}'; echo
on_node $N "systemctl is-active kubelet; journalctl -u kubelet --since -2min --no-pager | grep -iE 'unauthor|forbid' | tail -2 | cut -c1-250"
sleep 30
aws logs filter-log-events --log-group-name /aws/eks/$SID-cluster-eks/cluster --log-stream-name-prefix authenticator --start-time $(( ($(date +%s)-300)*1000 )) --filter-pattern '?denied ?"not found" ?error ?unknown' --query 'events[-3:].message' --output text | cut -c1-300
LAB=cluster-3 bash modules/cluster/faults/control-plane/rollback.sh
echo "=== cluster-3 v2 cordon"
LAB=cluster-3 VARIANT=2 bash modules/cluster/faults/control-plane/inject.sh; echo "inject rc=$?"
sleep 30; kubectl get nodes; kubectl -n app get pods -l app.kubernetes.io/name=opslab-app
sleep 60
aws logs filter-log-events --log-group-name /aws/eks/$SID-cluster-eks/cluster --log-stream-name-prefix kube-apiserver-audit --start-time $(( ($(date +%s)-300)*1000 )) --filter-pattern '{ $.objectRef.resource = "nodes" && $.verb = "patch" }' --query 'events[-2:].message' --output text | cut -c1-400
LAB=cluster-3 bash modules/cluster/faults/control-plane/rollback.sh
echo "=== final"; bash modules/cluster/baseline/verify.sh | tail -6
