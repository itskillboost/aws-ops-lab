#!/bin/bash
# K1 층 초기화 — 스택(<학번>-k1) 배포 뒤 start.sh 가 실행한다. 다시 실행해도 안전하다.
#   kubeconfig 갱신 → 노드 Ready 대기 → 기본 StorageClass(gp3) → Headlamp(웹 대시보드)와 로그인용 서비스 계정
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../common/eks.sh"
kube_login || { echo "❌ kubeconfig 갱신 실패 — 클러스터 $CLUSTER 가 있는지 확인하세요."; exit 1; }
echo "  kubeconfig: 컨텍스트 $SID → $CLUSTER"
echo "  노드 Ready 대기(최대 10분)"
kubectl wait --for=condition=Ready nodes --all --timeout=600s >/dev/null || { echo "❌ 노드가 Ready 가 되지 않았습니다."; exit 1; }

# 기본 StorageClass: gp3 (EBS CSI 드라이버). 기존 gp2 의 기본 표시는 뗀다
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations: { storageclass.kubernetes.io/is-default-class: "true" }
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
parameters: { type: gp3 }
YAML
kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class=false --overwrite >/dev/null 2>&1
echo "  StorageClass gp3 (기본)"

# Headlamp — NLB 로 열되, 접속 허용 IP 는 headlamp.sh 를 실행하기 전까지 아무도 못 들어오는 주소로 둔다
SRC=${HEADLAMP_SOURCE:-127.0.0.1/32}
kubectl create namespace headlamp --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace headlamp course=opslab --overwrite >/dev/null
helm upgrade --install headlamp "$EKS_ROOT/vendor/charts/headlamp" -n headlamp --wait --timeout 10m \
  --set image.registry="$(img_repo headlamp | cut -d/ -f1)" \
  --set image.repository="$(img_repo headlamp | cut -d/ -f2-)" \
  --set image.tag="$(img_tag headlamp)" \
  --set clusterRoleBinding.create=false \
  --set service.type=LoadBalancer \
  --set-string "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type=nlb" \
  --set-string "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-scheme=internet-facing" \
  --set-string "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-additional-resource-tags=Course=opslab\,Module=cluster\,Owner=$SID" \
  --set "service.loadBalancerSourceRanges={$SRC}" >/dev/null || { echo "❌ Headlamp 설치 실패"; exit 1; }
# 로그인 토큰을 발급할 관리용 서비스 계정(headlamp-admin) — 내 클러스터 안에서만 쓰는 열쇠
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata: { name: headlamp-admin, namespace: headlamp }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: headlamp-admin }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin }
subjects: [{ kind: ServiceAccount, name: headlamp-admin, namespace: headlamp }]
YAML
echo "  Headlamp 설치 완료 — 접속 준비: bash ~/opslab/common/headlamp.sh"
