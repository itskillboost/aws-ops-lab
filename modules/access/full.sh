#!/bin/bash
# access 따라잡기(start.sh access full) — 1단계 구축 명령 모음인 K4 층 설치 스크립트를 실행한다.
exec bash "$(dirname "$(readlink -f "$0")")/../../layers/k4-access.sh"
