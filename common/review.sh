#!/bin/bash
# 실습 검토 — 사람이 채점하지 않아도 무엇을 잘했고 무엇이 빠졌는지 스스로 확인한다. 점수는 매기지 않는다.
#   bash ~/opslab/common/review.sh workload-1   Lab 검토: 해결 기록(inject.sh done) 또는 원복 직후
#   bash ~/opslab/common/review.sh workload     모듈 검토: 하루 마무리, 반드시 cleanup.sh 보다 먼저
#   bash ~/opslab/common/review.sh final        과정 마지막 날: 나의 장애 대응 포트폴리오(~/opslab-work/portfolio.md)
# 결과 요약은 SSM Parameter Store /opslab/reviews/<Lab ID 또는 모듈ID> 에 남아 강사가 반 전체 현황을 본다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) source ~/opslab-env.sh}"
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
source "$ROOT/common/eks.sh"
[ -n "${1:-}" ] || { sed -n '2,6p' "$0" | sed 's/^#//'; exit 1; }
have_cluster && kube_login
exec python3 - "$ROOT" "$1" <<'PY'
import json, os, re, subprocess, sys, datetime
import yaml

ROOT, ARG = sys.argv[1], sys.argv[2]
SID = os.environ["SID"]
WORK = os.path.expanduser("~/opslab-work")
COURSE = os.path.join(ROOT, "courses", os.environ.get("COURSE", "skons") + ".yaml")
MARK = {"ok": "✅", "retry": "✅(재도전)", "part": "⚠️", "no": "❌"}

def sh(cmd, timeout=120):
    try:
        r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return 124, "시간 초과"

def ssm_get(name):
    rc, out = sh(f"aws ssm get-parameter --name '{name}' --query Parameter.Value --output text 2>/dev/null")
    return out.strip() if rc == 0 else None

def ssm_put(name, value):
    sh(f"aws ssm put-parameter --name '{name}' --type String --overwrite --value '{value}' >/dev/null")

def module_labs(mod):
    rows = []
    for line in open(os.path.join(ROOT, "modules", mod, "module.yaml")):
        m = re.match(r"\s*-\s*([a-z]+-\d+)\s*\|\s*([^|]+)\|\s*(\d+)\s*\|\s*([^|]+)\|\s*(.*)", line)
        if m:
            rows.append(dict(lab=m[1], fault=m[2].strip(), level=m[4].strip(), title=m[5].strip()))
    return rows

def filled_lines(path, template):
    """양식에 없던 줄(수강생이 쓴 줄) 중 내용이 있는 줄 수"""
    if not os.path.exists(path):
        return None
    tpl = set(l.strip() for l in open(template)) if os.path.exists(template) else set()
    n = 0
    for l in open(path):
        s = l.strip()
        if s and s not in tpl and not re.fullmatch(r"[|\-\s#>*]*", s) and not re.fullmatch(r"(\|\s*\d*\s*)+\|?", s):
            n += 1
    return n

def runbook_sections(path):
    """런북 5항목(## 1~5) 각각에 수강생이 쓴 줄이 있는지"""
    tpl = set(l.strip() for l in open(os.path.join(ROOT, "runbook", "TEMPLATE.md")))
    names = {1: "증상", 2: "확인 순서", 3: "원인", 4: "조치", 5: "재발 방지"}
    have, cur = {k: 0 for k in names}, None
    for l in open(path):
        m = re.match(r"##\s*(\d)\.", l)
        if m:
            cur = int(m[1]); continue
        s = l.strip()
        if cur in have and s and s not in tpl and not s.startswith("```") and not re.fullmatch(r"(\|\s*\d*\s*)+\|?|[-|\s]*", s):
            # "- 직접 원인:" 처럼 양식 머리말 뒤에 내용을 붙인 줄도 인정한다
            have[cur] += 1
    return {names[k]: v > 0 for k, v in have.items()}

def show(items, title):
    print(f"\n== {title}")
    for st, name, why, fix in items:
        print(f"  {MARK[st]} {name} — {why}")
        if st in ("part", "no") and fix:
            print(f"      ↳ 보완: {fix}")

# ─────────────────────────────── Lab 검토
def review_lab(lab):
    mod = lab.split("-")[0]
    row = next((r for r in module_labs(mod) if r["lab"] == lab), None)
    if not row:
        sys.exit(f"❌ Lab ID를 찾지 못했습니다: {lab}")
    fdir = os.path.join(ROOT, "modules", mod, "faults", row["fault"])
    items = []
    # 1) 가설
    h = filled_lines(os.path.join(WORK, mod, f"hypothesis-{lab}.md"), os.path.join(ROOT, "runbook", "HYPOTHESIS.md"))
    if h is None:
        items.append(("no", "가설 기록", "파일이 없습니다", f"~/opslab-work/{mod}/hypothesis-{lab}.md 를 채우세요(주입 전에 쓰는 것이 원칙)"))
    elif h >= 4:
        items.append(("ok", "가설 기록", f"작성한 줄 {h}개", ""))
    else:
        items.append(("part", "가설 기록", f"작성한 줄 {h}개(4줄 이상 권장)", "표의 '장애가 나면 이렇게 변할 것이다' 칸과 '가장 먼저 확인할 곳'을 채우세요"))
    # 2) 시각 기록과 해결 방식 (SSM 주입 기록 대조)
    meta = json.loads(ssm_get(f"/opslab/injections/{lab}") or "{}")
    stt = meta.get("state")
    if not meta:
        items.append(("no", "주입·해결 기록", "주입 기록이 없습니다", f"bash ~/opslab/common/inject.sh {lab}"))
    elif stt == "resolved":
        miss = [k for k, n in (("aware_at", "인지"), ("cause_at", "원인 확정")) if not meta.get(k)]
        if miss:
            items.append(("part", "시각 기록", "빠진 시각: " + ", ".join(miss), f"inject.sh done 은 다시 할 수 없으니 기록표에 직접 적으세요"))
        else:
            items.append(("ok", "시각 기록", f"주입 {meta['injected_at'][11:16]} → 인지 {meta['aware_at'][11:16]} → 원인 {meta['cause_at'][11:16]} → 복구 {meta['resolved_at'][11:16]}", ""))
        if meta.get("retry"):
            items.append(("retry", "해결 방식", "1차 원복 → 재도전 해결", ""))
        else:
            items.append(("ok", "해결 방식", "직접 해결", ""))
    elif stt == "rolled_back":
        items.append(("part", "해결 방식", "원복만 함(재도전 전)", f"bash ~/opslab/common/inject.sh retry {lab} → 해답을 보며 해결 → inject.sh done {lab}"))
    else:
        items.append(("no", "해결 방식", "장애가 아직 주입된 상태입니다", f"해결한 뒤 verify.sh → bash ~/opslab/common/inject.sh done {lab}"))
    # 3) verify
    rc, out = sh(f"bash '{fdir}/verify.sh'", 180)
    fails, lines = [], out.splitlines()
    for i, l in enumerate(lines):           # FAIL 줄과 바로 아래 들여쓴 상세 줄(예: 압박 노드 이름)을 함께 보여 준다
        if "[FAIL]" in l:
            det = [x.strip() for x in lines[i+1:i+3] if x.startswith("         ")]
            fails.append(" ".join([l.strip().replace("[FAIL] ", "")] + det))
    if rc == 0:
        items.append(("ok", "verify.sh", "정상 상태 판정 통과", ""))
    else:
        items.append(("no", "verify.sh", " / ".join(fails) if fails else "판정 실패", f"bash ~/opslab/modules/{mod}/faults/{row['fault']}/verify.sh 의 FAIL 항목부터 고치세요"))
    # 4) 재발 방지 (review.yaml)
    rv = yaml.safe_load(open(os.path.join(fdir, "review.yaml")))
    for c in rv.get("checks", []):
        rc, _ = sh(c["run"])
        items.append(("ok" if rc == 0 else "no", "재발 방지: " + c["name"], "적용됨" if rc == 0 else "확인되지 않음",
                      f"{c.get('fix','')} (다시 볼 곳: {c.get('ref','해답')})"))
    # 5) 런북
    rb = os.path.join(WORK, mod, f"runbook-{lab}.md")
    if not os.path.exists(rb):
        items.append(("no", "런북 초안", "파일이 없습니다", f"~/opslab-work/{mod}/runbook-{lab}.md 를 공통 양식으로 쓰세요"))
    else:
        secs = runbook_sections(rb)
        miss = [k for k, v in secs.items() if not v]
        if not miss:
            items.append(("ok", "런북 초안", "다섯 항목(증상·확인 순서·원인·조치·재발 방지) 모두 작성", ""))
        else:
            items.append(("part" if len(miss) < 5 else "no", "런북 초안", "빈 항목: " + ", ".join(miss), "해답의 '런북 예시'를 참고해 빈 항목을 채우세요"))
    show(items, f"Lab 검토: {lab} — {row['title']}")
    print("\n회고 질문")
    print("  1. 처음 세운 가설과 실제 원인은 어디서 갈렸나요? 무엇을 봤을 때 알았나요?")
    print("  2. 인지 → 원인 확정까지 가장 시간이 오래 걸린 단계는? 다음에는 무엇을 먼저 보겠습니까?")
    print("  3. 같은 장애가 운영 환경에서 나면 누구에게, 무엇을 근거로 보고하겠습니까?")
    summ = {"at": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M"),
            "items": {i[1][:40]: i[0] for i in items}}
    ssm_put(f"/opslab/reviews/{lab}", json.dumps(summ, ensure_ascii=False).replace("'", ""))
    return items

# ─────────────────────────────── 모듈 검토
def review_module(mod):
    items = []
    rc, out = sh(f"bash '{ROOT}/common/check.sh' {mod} all", 300)
    bad = [l.strip() for l in out.splitlines() if "❌" in l]
    items.append(("ok" if rc == 0 else "no", "구축 확인 지점(check.sh)", "모두 통과" if rc == 0 else (bad[0] if bad else "실패"),
                  f"bash ~/opslab/common/check.sh {mod} all 의 ❌ 항목을 다시 하세요"))
    bl = os.path.join(WORK, mod, "baseline.txt")
    items.append(("ok", "정상 상태 기준값", "baseline.txt 기록됨", "") if os.path.exists(bl) else
                 ("no", "정상 상태 기준값", "기록 없음", f"부하를 켜고 bash ~/opslab/modules/{mod}/baseline/verify.sh"))
    for r in module_labs(mod):
        s = ssm_get(f"/opslab/reviews/{r['lab']}")
        meta = json.loads(ssm_get(f"/opslab/injections/{r['lab']}") or "{}")
        if r["level"] == "필수":
            if not s:
                items.append(("no", f"[필수] {r['lab']}", "Lab 검토를 하지 않았습니다", f"bash ~/opslab/common/review.sh {r['lab']}"))
                continue
            st = list(json.loads(s)["items"].values())
            nok = sum(1 for x in st if x in ("ok", "retry"))
            grade = "ok" if nok == len(st) else ("part" if nok else "no")
            if grade == "ok" and "retry" in st:
                grade = "retry"
            items.append((grade, f"[필수] {r['lab']}", f"검토 항목 {nok}/{len(st)} 충족", f"bash ~/opslab/common/review.sh {r['lab']} 로 다시 확인"))
        else:
            done = meta.get("state") == "resolved"
            items.append(("ok" if done else "part", f"[심화] {r['lab']}", "수행함" if done else "아직 하지 않음(자율 심화)",
                          "수업 뒤에 혼자 해 볼 수 있습니다 — 자료·스크립트가 모두 공개되어 있습니다"))
    # 태그·라벨
    rc1, _ = sh("kubectl get ns -l course=opslab -o name | grep -q namespace/")
    rc2, out2 = sh(f"aws ec2 describe-volumes --filters Name=tag:kubernetes.io/created-for/pvc/name,Values=* "
                   f"--query \"Volumes[?!(Tags[?Key=='Owner' && Value=='{SID}'])].VolumeId\" --output text")
    untag = out2.split() if rc2 == 0 else []
    if rc1 == 0 and not untag:
        items.append(("ok", "태그·라벨", "실습 네임스페이스 라벨 course=opslab, 쿠버네티스가 만든 EBS 에도 Owner 태그", ""))
    else:
        items.append(("part", "태그·라벨", ("라벨 없는 네임스페이스 " if rc1 else "") + (f"태그 없는 EBS {len(untag)}개" if untag else ""),
                      "정리 스크립트가 태그·라벨로 찾습니다. 빠진 라벨은 kubectl label ns <이름> course=opslab"))
    show(items, f"모듈 검토: {mod}")
    print("\n회고 질문")
    print("  1. 오늘 다룬 장애 중 운영에서 가장 자주 날 것 같은 것은? 그 이유는?")
    print("  2. 클러스터 문제와 워크로드 문제를 가르는 첫 확인은 무엇이었나요?")
    print("  3. 오늘 쓴 런북 중 동료에게 그대로 넘겨도 되는 것은? 아니라면 무엇이 더 필요합니까?")
    print("\n다음: 비용 정리 → bash ~/opslab/common/cleanup.sh")
    ssm_put(f"/opslab/reviews/{mod}", json.dumps({"at": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M"),
                                                  "items": {i[1][:40]: i[0] for i in items}}, ensure_ascii=False).replace("'", ""))

# ─────────────────────────────── 과정 마무리: 포트폴리오
def final():
    days = yaml.safe_load(open(COURSE)).get("days", {})
    mods = [days[k] for k in sorted(days)]
    out = [f"# 나의 장애 대응 포트폴리오 — {SID}", "",
           f"- 과정: {yaml.safe_load(open(COURSE)).get('parent_course','')}",
           f"- 만든 날: {datetime.date.today()}", "",
           "## 1. 장애 대응 기록", "",
           "| Lab | 장애 | 주입 | 인지 | 원인 확정 | 복구 | 해결 방식 |", "|---|---|---|---|---|---|---|"]
    cover, books = [], []
    for mod in mods:
        if not os.path.exists(os.path.join(ROOT, "modules", mod, "module.yaml")):
            continue
        for r in module_labs(mod):
            m = json.loads(ssm_get(f"/opslab/injections/{r['lab']}") or "{}")
            t = lambda k: (m.get(k) or "-")[5:16].replace("T", " ")
            how = {"resolved": "재도전 해결" if m.get("retry") else "직접 해결", "rolled_back": "원복", "injected": "진행 중"}.get(m.get("state"), "-")
            if m:
                out.append(f"| {r['lab']} | {r['title']} | {t('injected_at')} | {t('aware_at')} | {t('cause_at')} | {t('resolved_at')} | {how} |")
            cover.append(f"- [{'x' if m.get('state') == 'resolved' else ' '}] {r['lab']} ({r['level']}) {r['title']}")
            rb = os.path.join(WORK, mod, f"runbook-{r['lab']}.md")
            if os.path.exists(rb) and filled_lines(rb, os.path.join(ROOT, "runbook", "TEMPLATE.md")):
                books.append(f"\n---\n\n<!-- {r['lab']} -->\n" + open(rb).read())
    out += ["", "## 2. 다룬 장애 목록", ""] + cover + ["", "## 3. 런북 모음"] + books
    p = os.path.join(WORK, "portfolio.md")
    os.makedirs(WORK, exist_ok=True)
    open(p, "w").write("\n".join(out) + "\n")
    print(f"✅ 포트폴리오를 만들었습니다: {p} (런북 {len(books)}편)")
    print("   반드시 내 PC 로 내려받으세요 — CloudShell 오른쪽 위 [작업] → [파일 다운로드] → 경로에 위 경로 입력")
    print("   계정은 과정 뒤 반납되므로, 내려받지 않으면 사라집니다.")

if ARG == "final":
    final()
elif re.fullmatch(r"[a-z]+-\d+", ARG):
    review_lab(ARG)
else:
    review_module(ARG)
PY
