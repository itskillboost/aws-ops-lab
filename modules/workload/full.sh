#!/bin/bash
# 따라잡기(start.sh workload full)·시험용: 1단계 구축 따라하기 명령 모음 = K2 층과 같다
exec bash "$(dirname "$(readlink -f "$0")")/../../layers/k2-workload.sh"
