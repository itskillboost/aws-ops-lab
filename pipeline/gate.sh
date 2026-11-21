#!/bin/bash
# 스캔 게이트 판정 — buildspec-scan.yml 이 부른다.  bash pipeline/gate.sh <등급별 개수 JSON> <저장소> <태그>
# GATE_SEVERITY 이상 등급의 취약점 수 합계가 GATE_MAX 를 넘으면 종료 코드 1(파이프라인 정지).
set -uo pipefail
C=$1; REPO=$2; TAG=$3; SEV=${GATE_SEVERITY:-CRITICAL}; MAX=${GATE_MAX:-0}
LEVELS="CRITICAL HIGH MEDIUM LOW INFORMATIONAL UNDEFINED"
[[ " $LEVELS " == *" $SEV "* ]] || { echo "❌ GATE_SEVERITY 값이 이상합니다: $SEV (CRITICAL|HIGH|MEDIUM|LOW 중 하나)"; exit 1; }
n=0; for l in $LEVELS; do
  c=$(jq -r --arg l "$l" '.[$l] // 0' "$C"); printf '   %-13s %s\n' "$l" "$c"
  n=$((n + c)); [ "$l" = "$SEV" ] && break
done
echo "== ${SEV} 이상 ${n}개 (허용 ${MAX}개)"
if [ "$n" -gt "$MAX" ]; then
  echo "❌ 스캔 게이트 차단 — 상위 취약점:"
  aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag="$TAG" --output text \
    --query "imageScanFindings.findings[?severity=='CRITICAL' || severity=='HIGH'] | [0:10].[severity,name,attributes[?key=='package_name'].value | [0],attributes[?key=='package_version'].value | [0]]" | sed 's/^/   /'
  exit 1
fi
echo "✅ 스캔 게이트 통과"
