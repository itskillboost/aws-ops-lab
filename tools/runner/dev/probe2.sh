source common/eks.sh; kube_login; export LAB=probe; source modules/cluster/node.sh
N=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
on_node $N "grep -o '\"podPidsLimit\": *[-0-9]*' /etc/kubernetes/kubelet/config.json; cat /etc/kubernetes/kubelet/config.json.d/*.conf | head -c 600; echo; cat /sys/fs/cgroup/kubepods.slice/pids.max; for f in /sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/*/pids.max; do echo \$f \$(cat \$f); done | head -3; ulimit -u"
kubectl run pidtest -n app --image=$(img_repo app):$(img_tag app) --restart=Never --command -- sh -c 'ulimit -u; cat /sys/fs/cgroup/pids.max; i=0; while [ $i -lt 3000 ]; do sleep 600 & i=$((i+1)); done; echo spawned; sleep 5; ps -e | wc -l'
sleep 40; kubectl -n app logs pidtest | tail -5; kubectl -n app get pod pidtest; kubectl -n app delete pod pidtest --now
