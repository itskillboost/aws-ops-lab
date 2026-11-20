#!/bin/bash
# 노드(EC2)에서 명령 실행 — SSH 키 없이 Session Manager Run Command(AWS-RunShellScript)로 실행하고 출력을 돌려준다.
#   on_node <노드 이름> "<명령>"     (장애 스크립트·review.yaml·check.sh 가 쓴다)
node_iid() { kubectl get node "$1" -o jsonpath='{.spec.providerID}' 2>/dev/null | awk -F/ '{print $NF}'; }
on_node() {
  local iid cid st i
  iid=$(node_iid "$1"); [ -n "$iid" ] || iid=$(aws ec2 describe-instances --filters Name=private-dns-name,Values="$1" \
      Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)
  cid=$(aws ssm send-command --instance-ids "$iid" --document-name AWS-RunShellScript --comment "opslab ${LAB:-check}" \
        --parameters "$(jq -nc --arg c "$2" '{commands:[$c]}')" --query Command.CommandId --output text) || return 1
  for i in $(seq 1 60); do
    st=$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$iid" --query Status --output text 2>/dev/null)
    case "$st" in Success|Failed|Cancelled|TimedOut) break ;; esac; sleep 2
  done
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$iid" --query StandardOutputContent --output text
  [ "$st" = Success ]
}
