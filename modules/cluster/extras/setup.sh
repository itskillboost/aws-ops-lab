#!/bin/bash
# cluster 모듈 주변 구성 — 수강생이 직접 만든 클러스터를 K1 층과 같은 상태로 맞추고, 진단 대상(샘플 앱·DB)을 올린다.
#   bash ~/opslab/modules/cluster/extras/setup.sh        (1단계 구축 5 — 약 10분. 다시 실행해도 안전하다)
# ① 강사 읽기 전용·FIS 접근 항목 ② OIDC 공급자 ③ 기본 애드온을 관리형으로 ④ StorageClass·Headlamp ⑤ 샘플 앱·PostgreSQL·Redis
# 이 단계가 빠지면 강사가 그날 내 클러스터를 볼 수 없고(①), 내일 이후 모듈의 IRSA(②)와 진단 대상(⑤)이 없다.
set -uo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)
source "$ROOT/common/eks.sh"
# 로그 켜기 같은 클러스터 설정 변경이 아직 진행 중(UPDATING)이면 끝날 때까지 기다린다(최대 15분)
for i in $(seq 1 45); do
  st=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.status --output text 2>/dev/null)
  [ "$st" = UPDATING ] || break; [ "$i" = 1 ] && echo "⏳ 클러스터 설정 변경이 진행 중입니다 — 끝날 때까지 기다립니다(보통 3~5분)"; sleep 20
done
have_cluster || { echo "❌ 클러스터 $CLUSTER 가 ACTIVE 가 아닙니다 — 구축 1을 먼저 끝내세요."; exit 1; }
kube_login
ACCT=$(aws sts get-caller-identity --query Account --output text)
echo "① 접근 항목: 강사 읽기 전용·FIS"
for x in "opslab-instructor-readonly AmazonEKSAdminViewPolicy" "opslab-fis AmazonEKSEditPolicy"; do
  set -- $x; arn="arn:aws:iam::$ACCT:role/$1"
  aws eks create-access-entry --cluster-name "$CLUSTER" --principal-arn "$arn" >/dev/null 2>&1
  aws eks associate-access-policy --cluster-name "$CLUSTER" --principal-arn "$arn" \
    --policy-arn "arn:aws:eks::aws:cluster-access-policy/$2" --access-scope type=cluster >/dev/null \
    && echo "   $1 → $2" || { echo "❌ $1 접근 항목 실패"; exit 1; }
done
echo "② OIDC 공급자(파드에 IAM 역할을 빌려줄 때 신원을 보증하는 창구)"
ISS=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.identity.oidc.issuer --output text)
if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | tr '\t' '\n' | grep -q "${ISS#https://}$"; then
  echo "   이미 있음"
else
  aws iam create-open-id-connect-provider --url "$ISS" --client-id-list sts.amazonaws.com \
    --tags Key=Course,Value=opslab Key=Module,Value=cluster Key=Owner,Value="$SID" >/dev/null && echo "   생성" || { echo "❌ OIDC 공급자 생성 실패"; exit 1; }
fi
echo "③ 기본 애드온(관리형) — VPC CNI·kube-proxy·CoreDNS·EBS CSI·스냅샷 컨트롤러·노드 모니터링 에이전트"
addon() {  # $1=이름 [$2=설정 JSON]
  aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$1" >/dev/null 2>&1 \
    || aws eks create-addon --cluster-name "$CLUSTER" --addon-name "$1" --resolve-conflicts OVERWRITE \
         --tags Course=opslab,Module=cluster,Owner="$SID" ${2:+--configuration-values "$2"} >/dev/null || return 1
}
for a in vpc-cni kube-proxy coredns snapshot-controller eks-node-monitoring-agent; do addon "$a" || { echo "❌ $a 실패"; exit 1; }; done
addon aws-ebs-csi-driver "{\"controller\":{\"extraVolumeTags\":{\"Course\":\"opslab\",\"Module\":\"base\",\"Owner\":\"$SID\"}}}" || { echo "❌ aws-ebs-csi-driver 실패"; exit 1; }
for a in vpc-cni kube-proxy coredns aws-ebs-csi-driver snapshot-controller eks-node-monitoring-agent; do
  aws eks wait addon-active --cluster-name "$CLUSTER" --addon-name "$a" || { echo "❌ $a 가 ACTIVE 가 되지 않음"; exit 1; }
done; echo "   모두 ACTIVE"
echo "④ StorageClass·Headlamp"
bash "$ROOT/layers/k1-cluster.init.sh" | sed 's/^/ /' || exit 1
echo "⑤ 진단 대상: metrics-server·PostgreSQL·Redis·샘플 앱"
bash "$ROOT/layers/k2-workload.sh" | sed 's/^/ /' || exit 1
echo "✅ 주변 구성 완료 — 다음: bash ~/opslab/common/headlamp.sh, bash ~/opslab/common/check.sh cluster all"
