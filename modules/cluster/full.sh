#!/bin/bash
# cluster 따라잡기(start.sh cluster full) — K1 층(클러스터 완료 상태) 위에 진단 대상인 샘플 앱·PostgreSQL·Redis 를 올린다.
set -uo pipefail
bash "$(dirname "$(readlink -f "$0")")/../../layers/k2-workload.sh"
