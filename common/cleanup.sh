#!/bin/bash
# 비용 정리 스크립트 — 모듈별 독립 실습: 매일 끝에 L0 층을 뺀 그날의 리소스를 모두 지운다.
# 실행 위치: CloudShell
#   bash ~/opslab/common/cleanup.sh          # 매일 마지막: L0 층을 뺀 전부 삭제 (확인 질문 있음)
#   bash ~/opslab/common/cleanup.sh status   # 남아 있는 실습 리소스와 시간당 과금 리소스 보기
#   bash ~/opslab/common/cleanup.sh final    # 과정 마지막 날: 위 삭제 + 장애 주입·검토 기록(SSM)·GitHub 토큰 시크릿 삭제
#   bash ~/opslab/common/cleanup.sh check    # 정리 확인: 시간당 과금 리소스(클러스터·노드·로드밸런서·NAT)가 0개인지 판정
# EKS 가 있으면 클러스터를 지우기 전에 쿠버네티스가 대신 만든 AWS 리소스(로드밸런서·EBS)부터 회수한다.
#   순서: Argo CD 앱 → LoadBalancer Service → Ingress → PVC → Karpenter NodePool → 스택(K층 → L층) → 시크릿·ECR → 잔존 검사
# L0 스택(<학번>-l0)과 그 리소스는 지우지 않는다(호스팅 영역 외 과금 없음).
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
MODE="${1:-day}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

status() {
  echo "== $SID 남은 실습 리소스 (L0 층 제외) =="
  echo "-- 스택 --"
  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
    --query "StackSummaries[?starts_with(StackName,'$SID-') && StackName!='$SID-l0'].[StackName,StackStatus]" --output text | sed 's/^/  /'
  echo "-- 시간당 과금 리소스 --"
  aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=state,Values=available,pending \
    --query 'NatGateways[].[NatGatewayId,Tags[?Key==`Name`]|[0].Value]' --output text | sed 's/^/  NAT /'
  aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value,State.Name]' --output text | sed 's/^/  EC2 /'
  aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'$SID-')].LoadBalancerName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  ALB /'
  aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,'$SID-')].TargetGroupName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  TG  /'
  aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?starts_with(AutoScalingGroupName,'$SID-')].AutoScalingGroupName" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  ASG /'
  { aws ec2 describe-transit-gateways --filters Name=tag:Owner,Values="$SID" Name=state,Values=available,pending,deleting \
      --query 'TransitGateways[].[TransitGatewayId,State]' --output text
    aws ec2 describe-transit-gateways --filters Name=tag:Name,Values="$SID-*" Name=state,Values=available,pending,deleting \
      --query 'TransitGateways[].[TransitGatewayId,State]' --output text; } | sort -u | sed '/^$/d;s/^/  TGW /'
  aws network-firewall list-firewalls --query "Firewalls[?starts_with(FirewallName,'$SID-')].FirewallName" --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d;s/^/  FW  /'
  aws ec2 describe-vpc-endpoints --filters Name=tag:Owner,Values="$SID" Name=vpc-endpoint-type,Values=Interface \
    --query 'VpcEndpoints[].[VpcEndpointId,ServiceName]' --output text | sed 's/^/  VPCE /'
  aws eks list-clusters --query "clusters[?starts_with(@,'$SID-')]" --output text | tr '\t' '\n' | sed '/^$/d;s/^/  EKS /'
  tagged elasticloadbalancing:loadbalancer | sed 's/^/  LB(태그) /'
  aws ec2 describe-volumes --filters Name=tag:Owner,Values="$SID" --query 'Volumes[].[VolumeId,State,Size]' --output text | sed 's/^/  EBS /'
}
tagged() {  # 태그 Owner=<학번> 이 붙은 리소스 ARN (쿠버네티스가 대신 만든 로드밸런서 등)
  aws resourcegroupstaggingapi get-resources --tag-filters Key=Owner,Values="$SID" Key=Course,Values=opslab \
    --resource-type-filters "$1" --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d'
}

eks_predelete() {  # 클러스터를 지우기 전에, 쿠버네티스가 대신 만든 AWS 리소스를 먼저 회수한다(안 하면 고아 리소스로 남는다)
  source "$ROOT/common/eks.sh"
  have_cluster || return 0
  kube_login || return 0
  echo "  EKS 리소스 회수: $CLUSTER"
  # ① Argo CD: 감시원(application-controller)을 먼저 멈추고 앱을 지운다 — 살아 있으면 지운 리소스를 다시 만든다
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 >/dev/null 2>&1
    for a in $(kubectl get applications.argoproj.io -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{" "}{end}'); do
      kubectl -n "${a%/*}" patch applications.argoproj.io "${a#*/}" --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
      kubectl -n "${a%/*}" delete applications.argoproj.io "${a#*/}" --wait=false >/dev/null 2>&1
    done; echo "    ① Argo CD 앱 삭제"
  fi
  # ② LoadBalancer Service(Headlamp NLB 등) ③ Ingress(ALB)
  kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
    | while read -r x; do [ -n "$x" ] && kubectl -n "${x%/*}" delete svc "${x#*/}" --wait=false >/dev/null; done; echo "    ② LoadBalancer Service 삭제"
  kubectl delete ingress -A --all --wait=false >/dev/null 2>&1; echo "    ③ Ingress 삭제"
  # ④ PVC(EBS) — 먼저 PVC 를 쓰는 워크로드를 0으로 줄여야 PVC 가 지워진다
  for ns in $(kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' | sort -u); do
    kubectl -n "$ns" scale statefulset --all --replicas=0 >/dev/null 2>&1
    kubectl -n "$ns" delete pvc --all --wait=false >/dev/null 2>&1
  done; echo "    ④ PVC 삭제"
  # ⑤ Karpenter 노드
  kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1 && kubectl delete nodepools.karpenter.sh --all --wait=false >/dev/null 2>&1 && echo "    ⑤ Karpenter NodePool 삭제"
  # 로드밸런서·EBS 가 실제로 사라질 때까지 최대 5분 기다린다
  for i in $(seq 1 30); do
    n=$(( $(tagged elasticloadbalancing:loadbalancer | wc -l) + $(kubectl get pv -o name 2>/dev/null | wc -l) ))
    [ "$n" -eq 0 ] && break; sleep 10
  done
  [ "$n" -eq 0 ] && echo "    로드밸런서·볼륨 회수 완료" || echo "    ⚠️ 로드밸런서·볼륨 $n 개가 아직 남아 있습니다 — 스택 삭제 뒤 잔존 검사에서 다시 봅니다"
}

eks_postdelete() {  # 스택 삭제 뒤: 시크릿 즉시 삭제(과정 내내 쓰는 GitHub 토큰은 제외), ECR 강제 삭제, 로그 그룹, 잔존 검사
  for s in $(aws secretsmanager list-secrets --filters Key=tag-key,Values=Owner Key=tag-value,Values="$SID" \
              --query "SecretList[?!(Tags[?Key=='Lifecycle' && Value=='course'])].Name" --output text 2>/dev/null); do
    aws secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery >/dev/null && echo "  시크릿 즉시 삭제: $s"
  done
  for r in $(aws ecr describe-repositories --query "repositories[?starts_with(repositoryName,'$SID-')].repositoryName" --output text 2>/dev/null); do
    aws ecr delete-repository --repository-name "$r" --force >/dev/null && echo "  ECR 저장소 삭제: $r"
  done
  for g in $(aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/$SID-" --query 'logGroups[].logGroupName' --output text) \
           $(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$SID-" --query 'logGroups[].logGroupName' --output text); do
    aws logs delete-log-group --log-group-name "$g" && echo "  로그 그룹 삭제: $g"
  done
  # 잔존 검사: 쿠버네티스가 만든 것까지 태그로 찾는다
  local left; left=$( { tagged elasticloadbalancing:loadbalancer; tagged elasticloadbalancing:targetgroup; tagged ec2:volume; tagged ec2:instance; } )
  if [ -n "$left" ]; then
    echo "  ⚠️ 태그가 붙은 잔존 리소스가 있습니다 — 콘솔에서 확인 후 삭제하세요:"; sed 's/^/    /' <<<"$left"
  fi
  # 클러스터가 지워진 뒤 남는 쿠버네티스 로드밸런서 보안 그룹(k8s-elb-*)과 사용 중이 아닌 ENI
  for g in $(aws ec2 describe-security-groups --filters Name=tag:kubernetes.io/cluster/"$SID-cluster-eks",Values=owned --query 'SecurityGroups[].GroupId' --output text 2>/dev/null); do
    aws ec2 delete-security-group --group-id "$g" 2>/dev/null && echo "  보안 그룹 삭제: $g"
  done
}

check() {  # 시간당 과금 리소스가 0개인지
  local n=0 x
  x=$(aws eks list-clusters --query "length(clusters[?starts_with(@,'$SID-')])" --output text); [ "$x" -eq 0 ] && echo "  ✅ EKS 클러스터 0개" || { echo "  ❌ EKS 클러스터 $x개"; n=1; }
  x=$(aws ec2 describe-instances --filters Name=tag:Owner,Values="$SID" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations[].Instances[])' --output text)
  [ "$x" -eq 0 ] && echo "  ✅ EC2(노드 포함) 0개" || { echo "  ❌ EC2 $x개"; n=1; }
  x=$(tagged elasticloadbalancing:loadbalancer | wc -l); y=$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?starts_with(LoadBalancerName,'$SID-')])" --output text)
  [ $((x+y)) -eq 0 ] && echo "  ✅ 로드밸런서(ALB·NLB) 0개" || { echo "  ❌ 로드밸런서 $((x+y))개"; n=1; }
  x=$(aws ec2 describe-nat-gateways --filter Name=tag:Owner,Values="$SID" Name=state,Values=available,pending --query 'length(NatGateways)' --output text)
  [ "$x" -eq 0 ] && echo "  ✅ NAT 게이트웨이 0개" || { echo "  ❌ NAT 게이트웨이 $x개"; n=1; }
  x=$(aws ec2 describe-volumes --filters Name=tag:Owner,Values="$SID" --query 'length(Volumes)' --output text)
  [ "$x" -eq 0 ] && echo "  ✅ EBS 볼륨 0개" || { echo "  ❌ EBS 볼륨 $x개"; n=1; }
  [ "$n" -eq 0 ] && echo "✅ 정리 확인 통과 — 오늘 과금되는 실습 리소스가 없습니다." || echo "❌ 남은 리소스가 있습니다. cleanup.sh 를 다시 실행하고, 그래도 남으면 강사를 부르세요."
  return $n
}

delete_all() {
  read -r -p "L0 층을 뺀 $SID 의 실습 리소스를 모두 삭제합니다. 학번($SID)을 입력하세요: " ans; [ "$ans" = "$SID" ] || exit 1
  # 1) 모듈별 정리 훅: 수강생이 CLI로 직접 만든 리소스 (modules/*/cleanup.sh)
  for h in "$ROOT"/modules/*/cleanup.sh; do bash "$h"; done
  # 1-1) 콘솔 "템플릿 파일 업로드"가 계정에 자동으로 만드는 버킷 cf-templates-<임의>-<리전>: 우리 템플릿 파일만 지우고, 비면 버킷도 지운다
  TPLS=$(find "$ROOT" -name '*.yaml' -exec grep -l AWSTemplateFormatVersion {} + 2>/dev/null | xargs -n1 basename | sort -u)
  for b in $(aws s3api list-buckets --query "Buckets[?starts_with(Name,'cf-templates-') && ends_with(Name,'-$AWS_REGION')].Name" --output text 2>/dev/null); do
    aws s3api list-object-versions --bucket "$b" --output json 2>/dev/null \
      | jq -r '(.Versions // []) + (.DeleteMarkers // []) | .[] | [.Key, .VersionId] | @tsv' \
      | while IFS=$'\t' read -r k v; do
          for t in $TPLS; do case "$k" in *"$t") aws s3api delete-object --bucket "$b" --key "$k" --version-id "$v" >/dev/null && echo "  콘솔 업로드 템플릿 삭제: $b/$k"; break;; esac; done
        done
    [ "$(aws s3api list-object-versions --bucket "$b" --query 'length([Versions,DeleteMarkers][])' --output text 2>/dev/null)" = 0 ] \
      && aws s3api delete-bucket --bucket "$b" 2>/dev/null && echo "  빈 버킷 삭제: $b"
  done
  # 2) 수강생이 만든 CloudWatch 알람 (<학번>-*)
  AL=$(aws cloudwatch describe-alarms --alarm-name-prefix "$SID-" --query 'MetricAlarms[].AlarmName' --output text)
  [ -n "$AL" ] && aws cloudwatch delete-alarms --alarm-names $AL && echo "  알람 삭제: $AL"
  # 2-1) EKS: 클러스터를 지우기 전에 쿠버네티스가 만든 로드밸런서·볼륨을 회수
  eks_predelete
  # 3) 스택 (L0 제외, 늦게 만든 것부터)
  for st in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
               --query "reverse(sort_by(StackSummaries[?starts_with(StackName,'$SID-') && StackName!='$SID-l0'],&CreationTime))[].StackName" --output text); do
    echo "  스택 삭제: $st"; aws cloudformation delete-stack --stack-name "$st"; aws cloudformation wait stack-delete-complete --stack-name "$st" || echo "  ⚠️ $st 삭제 실패 — 콘솔에서 이벤트 확인"
  done
  # 4) 스택 삭제가 남긴 Aurora 최종 스냅샷(이전 템플릿의 기본 삭제 정책) — 저장 비용이 나가므로 삭제
  for s in $(aws rds describe-db-cluster-snapshots --snapshot-type manual --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier,'$SID-l3-snapshot-')].DBClusterSnapshotIdentifier" --output text); do
    aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier "$s" >/dev/null && echo "  최종 스냅샷 삭제: $s"; done
  # 5) EKS 과정: 시크릿·ECR·로그 그룹·잔존 검사
  eks_postdelete
  rm -f ~/.opslab/start/"$SID"-*     # start.sh 층 완료 표시
}

case "$MODE" in
  status) status ;;
  day)    delete_all; status; echo "== 정리 확인"; check ;;
  check)  check ;;
  final)
    delete_all
    for p in /opslab/injections /opslab/reviews; do
      N=$(aws ssm get-parameters-by-path --path $p --recursive --query 'Parameters[].Name' --output text)
      [ -n "$N" ] && echo $N | xargs -n 10 aws ssm delete-parameters --names >/dev/null && echo "  기록 삭제: $p"
    done
    aws secretsmanager delete-secret --secret-id opslab/github-token --force-delete-without-recovery >/dev/null 2>&1 \
      && echo "  GitHub 토큰 시크릿 삭제 — GitHub(Settings → Developer settings → Personal access tokens)에서 토큰 자체도 폐기하세요"
    status; echo "== 정리 확인"; check ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
