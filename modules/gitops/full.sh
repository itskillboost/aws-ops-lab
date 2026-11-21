#!/bin/bash
# gitops 따라잡기(start.sh gitops full) — 1단계 구축 명령 모음인 K5 층 설치 스크립트를 실행한다.
exec bash "$(dirname "$(readlink -f "$0")")/../../layers/k5-gitops.sh"
