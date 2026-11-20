#!/bin/bash
# cluster-3 control-plane — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: ① 노드 역할 접근 항목(EC2_LINUX)과 노드 한 대의 kubelet 재시작 ② 모든 노드의 스케줄 금지(cordon),
#            app 네임스페이스의 서비스 계정 하나와 그 권한(ClusterRole·바인딩, 이름 opslab-night-maint)
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2)
case $V in
  1) # 노드 역할의 접근 항목을 지운다 → 노드가 관제탑에 "누구냐"고 거절당한다(인증 실패)
     ARN=$(for a in $(aws eks list-access-entries --cluster-name "$CLUSTER" --query 'accessEntries[]' --output text); do
             [ "$(aws eks describe-access-entry --cluster-name "$CLUSTER" --principal-arn "$a" --query accessEntry.type --output text)" = EC2_LINUX ] && echo "$a"
           done | head -1)
     [ -n "$ARN" ] || { echo "노드 역할 접근 항목을 찾지 못했습니다" >&2; exit 1; }
     save node_role "$ARN"; N=$(target_node); save node "$N"
     aws eks delete-access-entry --cluster-name "$CLUSTER" --principal-arn "$ARN"
     sleep 20
     on_node "$N" "systemctl restart kubelet" >/dev/null ;;     # 인증 토큰을 새로 받는 순간(보통 15분 안에 저절로 옴)을 앞당긴다
  2) # "야간 점검 봇" 서비스 계정이 모든 노드를 cordon → 새 파드가 들어갈 노드가 없다. 누가 했는지는 감사(audit) 로그에 남는다
     kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata: { name: night-maint, namespace: app, labels: { course: opslab } }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: opslab-night-maint, labels: { course: opslab } }
rules: [{ apiGroups: [""], resources: [nodes], verbs: [get, list, patch] }]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: opslab-night-maint, labels: { course: opslab } }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: opslab-night-maint }
subjects: [{ kind: ServiceAccount, name: night-maint, namespace: app }]
YAML
     T=$(kubectl -n app create token night-maint --duration=10m)
     for n in $(kubectl get nodes -o name); do kubectl --token "$T" cordon "$n" >/dev/null; done
     kubectl -n "$NS" rollout restart deploy "$DEP" >/dev/null ;;   # 마침 배포가 나간다 → 새 파드가 갈 곳이 없다
esac
record $V
