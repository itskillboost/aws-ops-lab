# 이론 그림 (지침 7.5)

모듈마다 `docs/diagrams/<모듈ID>/`에 draw.io 원본(`.drawio`)과 렌더링한 PNG를 함께 둔다.

- 고치기: app.diagrams.net 또는 draw.io 데스크톱에서 `.drawio`를 열어 수정
- PNG 다시 만들기: `bash tools/drawio/render.sh docs/diagrams/<모듈ID>/*.drawio`
- workload 는 `build.py`(파이썬)로 원본을 생성했다: `python3 docs/diagrams/workload/build.py`
- 색 규칙: AWS 운영 주황 · 네트워크 초록 · 노드 파랑 · 파드 진한 파랑 · 정상 연초록 · 장애 빨강 · 먼저 볼 곳 노랑 · Service·정책 보라
- 그림 안에 고객사 이름·Day 번호·날짜를 쓰지 않는다
