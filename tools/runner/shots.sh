#!/bin/bash
# Headlamp 화면 캡처 (작성자용) — 모듈 따라하기 페이지에 넣을 화면을 실제 클러스터에서 찍는다.
#   SID=s00 bash tools/runner/shots.sh workload
# 찍을 화면 목록: modules/<모듈>/shots.list (한 줄에 "파일이름 | Headlamp 경로", {POD}·{NODE} 는 앱 파드·첫 노드 이름, 이름이 -full 로 끝나면 전체 페이지)
# 찍은 뒤 SSM 파라미터 /opslab/tmp/upload 에 {"파일이름":{"url":…,"auth":…}} 가 들어올 때까지(최대 20분) 기다렸다가 그 주소로 올린다.
# (작성 환경에서 이 러너 밖으로 파일을 꺼낼 길이 Notion 업로드 주소뿐이라 이렇게 넘긴다.)
set -uo pipefail
: "${SID:?}"; MOD=${1:?모듈}; ROOT=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
L="$ROOT/modules/$MOD/shots.list"; [ -f "$L" ] || { echo "없음: $L"; exit 1; }
source "$ROOT/common/eks.sh"; kube_login
bash "$ROOT/common/headlamp.sh" "$(curl -s https://checkip.amazonaws.com)" >/dev/null
O=/tmp/shots; mkdir -p $O
export HL=$(kubectl -n headlamp get svc headlamp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export TOKEN=$(kubectl -n headlamp create token headlamp-admin --duration=1h)
export NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
export POD=$(kubectl -n app get pods -l app.kubernetes.io/name=opslab-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
# Argo CD 화면(ARGO_LOGIN·ARGO:경로) — 접속 허용 IP 는 위 headlamp.sh 가 함께 바꿨다
export ARGO_H=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
export ARGO_P=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
[ -n "$ARGO_H" ] && for i in $(seq 1 40); do curl -s -o /dev/null -m 5 "http://$ARGO_H/" && break; sleep 15; done
grep -vE '^\s*(#|$)' "$L" > $O/list.txt
for i in $(seq 1 40); do curl -s -o /dev/null -m 5 "http://$HL/" && break; sleep 15; done
cat > $O/shot.py <<'PY'
import os, time
from playwright.sync_api import sync_playwright
H=os.environ["HL"]; T=os.environ["TOKEN"]; AH=os.environ.get("ARGO_H",""); AP=os.environ.get("ARGO_P",""); POD=os.environ.get("POD",""); NODE=os.environ.get("NODE","")
rows=[l.split("|") for l in open("/out/list.txt")]
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={"width":1440,"height":900}, device_scale_factor=1.5)
    for name,path in [(r[0].strip(), r[1].strip().replace("{POD}",POD).replace("{NODE}",NODE)) for r in rows]:
        if path == "LOGIN":   # 로그인 화면을 찍고 토큰으로 로그인
            pg.goto(f"http://{H}/c/main/token", wait_until="networkidle", timeout=120000); time.sleep(3)
            pg.screenshot(path=f"/out/{name}.png")
            pg.get_by_label("ID token").first.fill(T); pg.get_by_role("button", name="Authenticate").click(); time.sleep(6)
            print("login", pg.url); continue
        if path == "ARGO_LOGIN":   # Argo CD 로그인 화면을 찍고 admin 으로 로그인
            pg.goto(f"http://{AH}/login", wait_until="domcontentloaded", timeout=120000); time.sleep(5)
            pg.screenshot(path=f"/out/{name}.png")
            pg.locator("input").nth(0).fill("admin"); pg.locator("input[type=password]").first.fill(AP)
            pg.get_by_role("button").filter(has_text="SIGN IN").first.click(); time.sleep(6)
            print("argo login", pg.url); continue
        if path.startswith("ARGO:"):
            pg.goto(f"http://{AH}{path[5:]}", wait_until="domcontentloaded", timeout=120000); time.sleep(10)   # Argo CD 화면은 실시간 연결을 계속 열어 두어 networkidle 이 오지 않는다
            pg.screenshot(path=f"/out/{name}.png", full_page=name.endswith("-full"))
            print("shot", name, pg.url, "::", pg.inner_text("body").replace("\n"," | ")[:400]); continue
        pg.goto(f"http://{H}{path}", wait_until="networkidle", timeout=120000); time.sleep(6)
        pg.screenshot(path=f"/out/{name}.png", full_page=name.endswith("-full"))
        print("shot", name, pg.url, "::", pg.inner_text("body").replace("\n"," | ")[:400])
    b.close()
PY
docker run --rm --network host -e HL -e TOKEN -e POD -e NODE -e ARGO_H -e ARGO_P -v $O:/out mcr.microsoft.com/playwright/python:v1.49.0-noble \
  sh -c "pip install -q playwright==1.49.0 2>/dev/null && python /out/shot.py"
echo "SHOTS_READY"; ls -la $O/*.png
for i in $(seq 1 120); do J=$(aws ssm get-parameter --name /opslab/tmp/upload --with-decryption --query Parameter.Value --output text 2>/dev/null) && break; sleep 10; done
echo "$J" | jq -r 'to_entries[]|[.key,.value.url,.value.auth]|@tsv' | while IFS=$'\t' read -r f u a; do
  echo "upload $f $(curl -s -o /dev/null -w '%{http_code}' -X POST -H "authorization: $a" -F "file=@$O/${f%.png}.png;type=image/png" "$u")"; done
aws ssm delete-parameter --name /opslab/tmp/upload 2>/dev/null; true
