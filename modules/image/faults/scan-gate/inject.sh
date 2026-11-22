#!/bin/bash
# image-3 scan-gate — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 내 Fork 오늘 브랜치(app/Dockerfile·app/CHANGES.md 커밋), 스캔 프로젝트(<학번>-image-scan)의 환경변수
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 2); base_save
OLD=$(img_tag python-old)     # 취약점이 많은 옛 기본 이미지(강사 미러)
case $V in
  1) # 개발자가 "검증된 옛 버전"이라며 기본 이미지를 오래된 태그로 고정한 커밋
     commit app/Dockerfile "기본 이미지를 검증된 버전으로 고정" "s#/python:3\\.12-slim#/python:$OLD#" ;;
  2) # 스캔 게이트 기준을 잘못 바꿨다 — LOW 이상 0개(사실상 모든 이미지 차단) + 새 릴리스
     project_envset "$PS" GATE_SEVERITY LOW; sleep 5
     release "결제 안내 문구 수정" ;;
esac
record $V
