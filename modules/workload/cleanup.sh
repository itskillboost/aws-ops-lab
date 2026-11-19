#!/bin/bash
# workload 정리 훅 — 매일 cleanup.sh 가 부른다. 수강생이 CLI 로 직접 만든 것(풀스루 캐시 규칙)을 지운다.
: "${SID:?}"
aws ecr delete-pull-through-cache-rule --ecr-repository-prefix "$SID-workload" >/dev/null 2>&1 && echo "  ECR 풀스루 캐시 규칙 삭제: $SID-workload"
true
