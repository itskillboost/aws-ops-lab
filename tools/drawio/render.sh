#!/bin/bash
# 이론 그림 렌더링 — draw.io 원본을 같은 이름의 PNG(2배 해상도, 여백 자름)로 만든다(지침 7.5).
#   bash tools/drawio/render.sh docs/diagrams/workload/*.drawio
# 필요: python3, playwright(pip), Pillow, Chrome 또는 playwright chromium. draw.io 뷰어 스크립트는 처음 한 번 GitHub 에서 받는다.
# 주의: 뷰어는 화면에 보이는 요소만 그리므로 요소 크기를 고정해 렌더링한다. AWS·쿠버네티스 공식 아이콘(스텐실)은 외부에서 받아야 해 기본 도형을 권장한다.
set -euo pipefail
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd); W="$D/.work"; mkdir -p "$W"
[ -s "$W/viewer-static.min.js" ] || curl -fsSL -o "$W/viewer-static.min.js" https://raw.githubusercontent.com/jgraph/drawio/dev/src/main/webapp/js/viewer-static.min.js
PORT=8765; (cd "$W" && python3 -m http.server $PORT >/dev/null 2>&1) & SRV=$!; trap 'kill $SRV' EXIT; sleep 1
python3 "$D/render.py" $PORT "$@"
