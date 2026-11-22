# 이론 강의용 draw.io 다이어그램 생성기 — 기본 도형만 사용(어디서 열어도 동일하게 보이도록)
import html
class D:
    def __init__(s, name): s.name=name; s.cells=[]; s.n=0
    def _id(s): s.n+=1; return f"c{s.n}"
    def box(s, label, x, y, w, h, style="", parent="1"):
        i=s._id()
        st="rounded=1;whiteSpace=wrap;html=1;arcSize=8;fontSize=13;"+style
        s.cells.append(f'<mxCell id="{i}" value="{html.escape(html.escape(label,quote=False)).replace(chr(10),"&lt;br&gt;")}" style="{st}" vertex="1" parent="{parent}"><mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i
    def group(s, label, x, y, w, h, style=""):
        return s.box(label, x, y, w, h, "verticalAlign=top;align=left;spacingLeft=10;spacingTop=4;fontStyle=1;"+style)
    def text(s, label, x, y, w, h, style=""):
        return s.box(label, x, y, w, h, "text;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;"+style)
    def edge(s, a, b, label="", style="", points=None):
        i=s._id()
        st="edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;endFill=1;strokeWidth=2;fontSize=12;labelBackgroundColor=#ffffff;"+style
        s.cells.append(f'<mxCell id="{i}" value="{html.escape(label)}" style="{st}" edge="1" parent="1" source="{a}" target="{b}"><mxGeometry relative="1" as="geometry">'+(('<Array as="points">'+''.join(f'<mxPoint x="{x}" y="{y}"/>' for x,y in points)+'</Array>') if points else '')+'</mxGeometry></mxCell>')
    def xml(s):
        return ('<mxfile host="opslab"><diagram name="'+s.name+'"><mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" page="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>'
                + "".join(s.cells) + '</root></mxGraphModel></diagram></mxfile>')
    def save(s, path): open(path,"w").write(s.xml())

# 색
AWS="fillColor=#FFF4E5;strokeColor=#ED7100;"; VPC="fillColor=#F2F8EC;strokeColor=#7AA116;dashed=1;"
SUB="fillColor=#E9F3E6;strokeColor=#7AA116;"; NODE="fillColor=#EAF2FB;strokeColor=#2F6FB3;"
POD="fillColor=#326CE5;fontColor=#ffffff;strokeColor=#1F4FB0;fontStyle=1;"; SYS="fillColor=#DAE8FC;strokeColor=#6C8EBF;"
OK="fillColor=#D5E8D4;strokeColor=#82B366;"; BAD="fillColor=#F8CECC;strokeColor=#B85450;"; NOTE="fillColor=#FFF2CC;strokeColor=#D6B656;"
GRAY="fillColor=#F5F5F5;strokeColor=#666666;"; CP="fillColor=#FFE6CC;strokeColor=#D79B00;"






P="docs/diagrams/image/"
SVC="fillColor=#E1D5E7;strokeColor=#9673A6;"
GIT="fillColor=#F5F5F5;strokeColor=#333333;"
W="fillColor=#FFFFFF;strokeColor=#2F6FB3;"

# ① 오늘 환경의 아키텍처
d=D("1. 오늘 만드는 이미지 파이프라인")
d.group("GitHub 내 Fork — 오늘 브랜치",20,20,300,600,GIT)
me=d.box("나 (CloudShell ~/fork)\napp/app.py 고침 → git push",35,60,270,60,NOTE+"fontStyle=1;")
ga=d.box("app/ (앱 코드·Dockerfile)",35,150,270,45,GIT+"fontStyle=1;")
gp=d.box("pipeline/ (빌드 명세 3개\n+ 스캔 게이트 gate.sh)",35,210,270,55,GIT)
gv=d.box("gitops/apps/values.yaml\nreleaseRepository · releaseTag\n(파이프라인이 커밋)",35,420,270,75,SVC+"fontStyle=1;")
d.text("app/·pipeline/ 이 바뀔 때만 파이프라인이 깨어난다\n(gitops/ 커밋은 깨우지 않음 → 무한 반복 없음)",35,290,270,80,"fontStyle=2;fontSize=12;whiteSpace=wrap;")
d.edge(me,ga,"","exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
d.group("AWS — CodePipeline (컨베이어 벨트)",350,20,560,330,AWS)
s1=d.box("Source\nGitHub 연결\n(CodeConnections)",365,60,120,80,CP+"fontStyle=1;")
s2=d.box("Build\nCodeBuild\n도커 빌드·푸시\n태그=커밋 7자리",500,60,125,80,CP+"fontStyle=1;")
s3=d.box("Scan\nCodeBuild\n스캔 게이트\nCRITICAL 0개",640,60,120,80,CP+"fontStyle=1;")
s4=d.box("Deploy\nCodeBuild\nvalues.yaml 에\n태그 커밋",775,60,120,80,CP+"fontStyle=1;")
d.edge(s1,s2,""); d.edge(s2,s3,""); d.edge(s3,s4,"")
ecr=d.box("ECR 내 저장소 <학번>-image-app\n태그 불변 · 푸시하면 스캔 · 수명주기(최근 20개)",365,190,330,70,AWS+"fontStyle=1;")
sm=d.box("Secrets Manager\nopslab/github-token",715,190,180,70,AWS)
d.text("주변 구성 스택(<학번>-image-env):\n역할 2개(권한 경계) + 산출물 버킷",365,275,290,50,"fontStyle=2;fontSize=12;")
d.edge(s2,ecr,"푸시","exitX=0.5;exitY=1;entryX=0.4;entryY=0;")
d.edge(sm,s4,"토큰","exitX=0.5;exitY=0;entryX=0.5;entryY=1;dashed=1;")
d.edge(gp,s1,"① 깨움","exitX=1;exitY=0.5;entryX=0;entryY=0.5;",points=[(335,237),(335,100)])
d.edge(s4,gv,"④ 커밋","exitX=1;exitY=0.5;entryX=0.5;entryY=1;",points=[(930,100),(930,650),(170,650)])
d.group("EKS 클러스터",350,380,560,240,NODE)
ac=d.box("Argo CD (감시원)\nopslab-root → opslab-prod\nGit 이 바뀌면 동기화",365,420,220,80,SYS+"fontStyle=1;")
pd=d.box("app 네임스페이스\nopslab-app 파드\n이미지 = 내 ECR:태그",640,420,240,80,POD)
d.edge(gv,ac,"⑤ 읽기","exitX=1;exitY=0.3;entryX=0;entryY=0.5;")
d.edge(ac,pd,"⑥ 적용")
d.edge(ecr,pd,"⑦ 노드가 이미지 받기","exitX=0.955;exitY=1;entryX=0.3;entryY=0;dashed=1;",points=[(680,365),(712,365)])
d.text("파이프라인은 클러스터에 직접 손대지 않는다 — Git 에 적고, 반영은 Argo CD 가 한다",365,530,520,60,"fontStyle=2;fontSize=12;whiteSpace=wrap;")
d.save(P+"01-architecture.drawio")

# ② 파이프라인의 Git 커밋 구조
d=D("2. 파이프라인의 Git 커밋 구조")
d.text("오늘 브랜치 opslab/image-<날짜> 의 커밋 (아래로 갈수록 최근)",20,10,700,30,"fontStyle=1;")
rows=[("a1b2c3d","과정 태그에서 시작(start.sh)",GIT,"—"),
      ("e4f5a6b","image: a1b2c3d 배포 (빌드 1)",SVC,"파이프라인 — 첫 실행"),
      ("9c8d7e6","인사말에 학번 추가",NOTE,"나 — app/ 변경 → 파이프라인 깨움"),
      ("1f2e3d4","image: 9c8d7e6 배포 (빌드 2)",SVC,"파이프라인 — gitops/ 만 바꿈 → 안 깨움")]
prev=None
for i,(sha,msg,st,who) in enumerate(rows):
    y=50+i*95
    c=d.box(sha+"  "+msg,20,y,380,55,st+"fontStyle=1;align=left;spacingLeft=10;")
    d.text(who,420,y,330,55,"fontSize=12;")
    if prev: d.edge(prev,c,"")
    prev=c
d.group("이미지 태그 = 소스 커밋의 앞 7자리",780,50,380,370,OK)
d.box("ECR\n:a1b2c3d (빌드 1)\n:9c8d7e6 (빌드 2)",800,90,340,90,AWS+"fontStyle=1;")
d.text("• 태그만 보면 어느 커밋으로 만든 이미지인지 안다\n• 앱 응답 /api 의 build 도 같은 값\n• 운영에 무엇이 나가 있는지 = Git 의 releaseTag\n• 되돌리기 = releaseTag 를 이전 값으로 커밋(git revert)",800,195,340,150,"fontSize=12;whiteSpace=wrap;")
d.save(P+"02-commit-flow.drawio")

# ③ 태그 전략 · 수명주기 · 스캔 게이트
d=D("3. 태그 전략 · 수명주기 · 스캔 게이트")
d.group("태그 불변(IMMUTABLE) — 같은 이름표는 다시 못 붙인다",20,20,360,300,SYS)
d.box("푸시 :9c8d7e6 → ✅",40,65,320,45,OK)
d.box("같은 :9c8d7e6 다시 푸시 → ❌ 거부\n(빌드 단계는 '이미 있으면 건너뜀')",40,125,320,60,BAD)
d.box(":latest 같은 움직이는 태그를 쓰지 않는 이유\n= 어제와 오늘 같은 이름, 다른 내용",40,200,320,60,NOTE)
d.group("수명주기 정책 — 창고 정리 규칙",400,20,360,300,AWS)
d.box("규칙 1: 태그 없는 이미지 → 1일 뒤 삭제",420,65,320,45,GRAY)
d.box("규칙 2: 이미지가 20개 넘으면 오래된 것부터 삭제",420,125,320,45,GRAY)
d.box("주의: 운영이 쓰는 옛 태그도\n'오래됐다'는 이유로 지워질 수 있다\n→ 미리보기(lifecycle preview)로 확인",420,190,320,75,NOTE)
d.group("스캔 게이트 — 출고 전 검사대",780,20,380,300,OK)
lv=[("CRITICAL","0개 허용",BAD),("HIGH","세지 않음",NOTE),("MEDIUM","세지 않음",GRAY),("LOW","세지 않음",GRAY)]
for i,(a,b,st) in enumerate(lv):
    d.box(a+" — "+b,800,65+i*45,340,38,st)
d.text("기준: GATE_SEVERITY=CRITICAL, GATE_MAX=0\n기준을 낮추면(LOW) 정상 이미지도 막힌다",800,250,340,55,"fontSize=12;whiteSpace=wrap;")
d.save(P+"03-tag-lifecycle-gate.drawio")

# ④ 진단 순서
d=D("4. 진단 순서 — 새 버전이 운영에 안 보일 때")
q=d.box("① 파이프라인 최근 실행: 어느 단계에서 멈췄나?",20,20,1140,50,NOTE+"fontStyle=1;")
b1=d.box("Source 실패\nGitHub 연결 상태\n(AVAILABLE?)",20,110,210,95,BAD)
b2=d.box("Build 실패\nCodeBuild 단계(phase)\n→ 로그 마지막 오류\n(기본 이미지·권한·명세)",250,110,250,95,BAD)
b3=d.box("Scan 실패\n게이트 로그의 등급별 개수\n→ ECR 스캔 결과(CVE)\n→ 기본 이미지·기준 변경",520,110,280,95,BAD)
b4=d.box("모두 성공인데 운영이 그대로\n= 빌드 성공 후 배포 실패\n→ ②로",820,110,340,95,CP+"fontStyle=1;")
for b in (b1,b2,b3,b4): d.edge(q,b,"","exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
c2=d.box("② 오늘 브랜치에 'image: <태그>' 커밋이 있나?\n(gitfile.sh log)\n없음 → Deploy 단계 로그·\n배포 프로젝트 환경변수(브랜치·토큰)",820,240,340,95,SYS)
c3=d.box("③ Argo CD 운영 앱: 리비전·이미지 파라미터가 새 태그인가?\n(argocd app get opslab-prod)",820,360,340,75,SYS)
c4=d.box("④ 파드: 새 파드가 이미지를 받았나?\nImagePullBackOff → 이미지 주소·ECR 에 태그가 있나",820,455,340,75,SYS)
d.edge(b4,c2,""); d.edge(c2,c3,""); d.edge(c3,c4,"")
d.box("기록을 본다: 커밋 기록(누가 무엇을) · CloudTrail(권한·프로젝트 설정 변경) · 파이프라인 실행 기록",20,240,780,60,GRAY)
d.box("원인을 고친 뒤: 커밋을 푸시하거나 [변경 사항 릴리스]로 새 실행\n(실패한 실행을 '다시 시도'하면 고장 난 소스로 다시 돈다)",20,320,780,70,NOTE)
d.save(P+"04-diagnosis.drawio")
print("saved")
