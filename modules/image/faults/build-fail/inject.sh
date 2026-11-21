#!/bin/bash
# image-2 build-fail — inject. 직접 실행하지 말고 common/inject.sh 로 호출한다.
# 영향 범위: 내 Fork 오늘 브랜치(app/Dockerfile·pipeline/buildspec-build.yml·app/CHANGES.md 커밋), 빌드 역할의 거부 정책
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
V=$(pick_variant 3); base_save
case $V in
  1) # 기본 이미지 태그 오류 — 없는 태그(3.21)로 바꾼 커밋
     commit app/Dockerfile "기본 이미지를 최신 파이썬으로" 's#/python:3\.12-slim#/python:3.21-slim#' ;;
  2) # 빌드 역할의 ECR 푸시 권한이 막혔다(보안 점검에서 붙인 거부 정책) + 새 릴리스
     put_deny '["ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload","ecr:PutImage"]'; sleep 10
     release "주문 화면 문구 수정" ;;
  3) # 빌드 명세(buildspec) 오류 — 들여쓰기에 탭 문자가 들어가 YAML 을 읽을 수 없다
     commit pipeline/buildspec-build.yml "빌드 명세 정리" 's#^      - echo "== 결과#\t- echo "== 결과#' ;;
esac
record $V
