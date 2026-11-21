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





P="docs/diagrams/gitops/"
SVC="fillColor=#E1D5E7;strokeColor=#9673A6;"
GIT="fillColor=#F5F5F5;strokeColor=#333333;"
W="fillColor=#FFFFFF;strokeColor=#2F6FB3;"
# ① 오늘 환경의 아키텍처
d=D("1. 오늘 만드는 GitOps 구조")
d.group("GitHub 내 Fork — 오늘 브랜치 (정답)",20,20,330,560,GIT)
ga=d.box("gitops/apps/ (앱 목록 = 목차)\n templates/prod.yaml → opslab-prod\n templates/dev.yaml → opslab-dev",35,60,300,85,GIT+"fontStyle=1;align=left;spacingLeft=8;")
ge=d.box("gitops/envs/ (환경별 기입 값)\n prod/values.yaml  (Vault·HPA·점검 훅)\n dev/values.yaml   (파드 1개, DB 없음)",35,165,300,85,GIT+"align=left;spacingLeft=8;")
gc=d.box("charts/opslab-app/ (설치 틀)\nDeployment·Service·HPA\nConfigMap(wave -1)·점검 Job(PreSync)",35,270,300,85,GIT+"align=left;spacingLeft=8;")
me=d.box("나 (CloudShell ~/fork)\ngit commit → git push",35,395,300,60,NOTE+"fontStyle=1;")
d.text("학번·계정 ID 는 Git 에 쓰지 않는다 → 루트 앱이 값으로 넘긴다",35,470,300,50,"fontStyle=2;fontSize=12;whiteSpace=wrap;")
d.edge(me,gc,"푸시","exitX=0.5;exitY=0;entryX=0.5;entryY=1;")
d.group("EKS 클러스터",380,20,580,560,NODE)
d.group("argocd 네임스페이스 — Argo CD (감시원)",395,55,550,215,W)
rs=d.box("repo-server\nGit 을 받아 Helm 으로\n매니페스트를 만든다",410,95,150,80,SYS+"fontStyle=1;")
ct=d.box("application-controller\nGit ↔ 클러스터 비교\n(1분마다)\n동기화·자동 치유",625,95,165,80,SYS+"fontStyle=1;")
sv=d.box("server\n(화면·CLI)\nNLB, 내 PC IP 만",805,95,125,80,SYS)
rd=d.box("redis (캐시)",410,190,150,40,SYS)
ap=d.box("Application\nopslab-root → opslab-prod · opslab-dev",625,190,305,60,SVC+"fontStyle=1;")
d.group("app (운영 prod)",395,290,270,270,W)
p1=d.box("opslab-app 파드 2~6개\n(HPA)\n+ Vault Agent 사이드카",410,325,240,80,POD)
db=d.box("PostgreSQL · Redis\n(GitOps 밖, helm)",410,420,240,50,GRAY)
ing=d.box("Ingress → ALB\n(GitOps 밖, K3 층)",410,485,240,55,GRAY)
d.group("app-dev (개발 dev)",680,290,265,270,W)
p2=d.box("opslab-app 파드 1개\nAPP_VERSION dev\nDB·캐시 없음",695,325,235,80,POD)
d.text("같은 차트 + 다른 values\n= 환경 분리",695,430,235,60,"fontStyle=2;align=center;")
d.edge(ga,rs,"① 읽기","exitX=1;exitY=0.5;entryX=0;entryY=0.5;",points=[(370,102),(370,135)])
d.edge(rs,ct,"②")
d.edge(ap,p1,"③ 적용(Sync)","exitX=0.25;exitY=1;entryX=0.8;entryY=0;",points=[(701,280),(602,280)])
d.edge(ap,p2,"","exitX=0.75;exitY=1;entryX=0.8;entryY=0;",points=[(854,280),(883,280)])
d.edge(ct,ap,"","dashed=1;")
d.group("AWS",990,20,190,560,AWS)
d.box("Secrets Manager\nopslab/github-token\n(Fork 읽기·쓰기 토큰)",1000,60,170,80,AWS+"fontStyle=1;")
d.box("NLB\nArgo CD 화면",1000,160,170,55,AWS)
d.box("ALB\n사용자 → 운영 앱",1000,235,170,55,AWS)
d.save(P+"01-architecture.drawio")

# ② 커밋이 클러스터에 반영되는 길
d=D("2. 커밋이 반영되는 길 (Sync)")
st=[("① 커밋·푸시","git push → 오늘 브랜치\n끝 커밋이 바뀐다"),("② 감지","1분마다(또는 Refresh)\nGit 을 다시 본다"),("③ 렌더링","repo-server:\nHelm 차트 + valueFiles\n+ 매개변수 → 매니페스트"),("④ 비교(diff)","controller: Git ↔ 클러스터\n다르면 OutOfSync"),("⑤ 동기화(Sync)","자동 동기화가 켜져 있으면\n바로 적용 → Synced")]
ids=[]
for i,(t,v) in enumerate(st):
    ids.append(d.box(t+"\n"+v,20+i*232,30,212,105,(NOTE if i==0 else SYS)+"fontStyle=1;"))
for i in range(4): d.edge(ids[i],ids[i+1],"")
d.group("⑤ 동기화 안에서의 순서 — 앞 단계가 건강(Healthy)해야 다음으로",20,170,1140,190,OK)
w=[("PreSync 훅","배포 전 점검 Job\n(DB 접속 확인)\n실패 → 동기화 중단"),("wave -1","앱 설정 ConfigMap\n(앱이 읽을 것을 먼저)"),("wave 0","Deployment·Service·HPA\n새 파드가 Ready 될 때까지 기다림"),("건강 판정","모든 리소스 Healthy\n→ Synced·Healthy\n(Progressing 이면 기다림)")]
wi=[]
for i,(t,v) in enumerate(w):
    wi.append(d.box(t+"\n"+v,40+i*280,210,250,120,"fillColor=#FFFFFF;strokeColor=#82B366;fontStyle=1;"))
for i in range(3): d.edge(wi[i],wi[i+1],"")
d.group("동기화가 멈추는 곳 (gitops-3·5·6)",20,390,1140,140,NOTE)
for i,t in enumerate(["③ 렌더링 실패\nvalues 파일 없음\n→ ComparisonError","③④ 부품 고장\nrepo-server 0 · 토큰 만료\n→ ComparisonError","PreSync 훅 실패\n→ SyncFailed\n(hook failed)","wave 순서 오류\n앱이 설정을 못 찾음\n→ waiting for healthy","새 파드 미준비\nreadiness 실패\n→ Progressing 고착"]):
    d.box(t,40+i*224,425,205,90,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.save(P+"02-sync-flow.drawio")

# ③ 동기화 정책과 자동 치유
d=D("3. 수동 변경과 자동 치유")
g=d.box("Git (정답)\nAPP_ERROR_RATE \"0\"\nreplicas 2",20,60,200,90,GIT+"fontStyle=1;")
c=d.box("클러스터 (실제)\nDeployment opslab-app",440,60,220,90,POD)
k=d.box("사람: kubectl set env\nAPP_ERROR_RATE=0.5",440,210,220,65,BAD+"fontStyle=1;")
d.edge(g,c,"Sync","exitX=1;exitY=0.3;entryX=0;entryY=0.3;")
d.edge(c,g,"diff → OutOfSync","dashed=1;exitX=0;exitY=0.7;entryX=1;entryY=0.7;")
d.edge(k,c,"수동 변경")
d.box("selfHeal: true (자동 치유)\n→ 몇 초 안에 Git 값으로 되돌림\n긴급 조치도 되돌린다!\n→ 고칠 곳은 Git",720,40,300,100,OK+"fontStyle=1;")
d.box("selfHeal: false\n→ OutOfSync 로 표시만 하고 그대로 둠\n누가 바꿨는지 모른 채 장애가 남는다",720,160,300,90,NOTE)
d.group("HPA 와 replicas — 둘 다 파드 수를 정하려 하면",20,310,1000,170,"fillColor=#FFFFFF;strokeColor=#9673A6;")
h=d.box("HPA: 최소 3개",40,355,180,55,SVC+"fontStyle=1;")
a=d.box("Argo CD: Git 의 replicas 2",300,355,220,55,SYS+"fontStyle=1;")
d.edge(h,a,"3으로","exitX=1;exitY=0.3;entryX=0;entryY=0.3;"); d.edge(a,h,"2로","exitX=0;exitY=0.7;entryX=1;entryY=0.7;")
d.box("해결: ignoreDifferences /spec/replicas\n+ RespectIgnoreDifferences=true\n→ 파드 수는 HPA 에게 맡긴다",580,345,420,80,OK+"fontStyle=1;")
d.text("서로 되돌리기(세대 번호가 계속 올라감, 파드가 생겼다 사라짐)",40,430,500,30,"fontStyle=2;")
d.save(P+"03-self-heal.drawio")

# ④ 진단 순서
d=D("4. GitOps 장애 진단 순서")
s=d.box("증상부터\n(사용자 오류·배포 미반영)",20,170,180,80,NOTE+"fontStyle=1;")
a=d.box("① argocd app list / get\nSync · Health · 마지막 작업",250,170,220,80,SYS+"fontStyle=1;")
d.edge(s,a,"")
b1=d.box("CONDITION 에 ComparisonError\n→ values 경로 · 저장소 연결\n(argocd repo list)\n· repo-server Ready?",530,20,280,95,GRAY)
b2=d.box("마지막 작업 Failed·Running\n→ 메시지: hook failed /\nwaiting for healthy (wave)\n→ 훅 Job 로그 · 파드 describe",530,130,280,105,GRAY)
b3=d.box("OutOfSync 가 계속 바뀜\n→ argocd app diff\n자동 치유·HPA·사람이 다툼",530,250,280,85,GRAY)
b4=d.box("Synced·Healthy 인데 장애\n→ 리비전 = 브랜치 끝?\n아니면 controller 멈춤\n맞으면 커밋 내용이 원인",530,350,280,95,GRAY)
for x,yy in ((b1,67),(b2,182),(b3,292),(b4,397)): d.edge(a,x,"","exitX=1;exitY=0.5;entryX=0;entryY=0.5;",points=[(500,210),(500,yy)])
f=d.box("② 무엇이 바뀌었나\ngit log · argocd app history\n(누가 언제 어떤 커밋)",870,150,280,90,"fillColor=#FFE6CC;strokeColor=#D79B00;fontStyle=1;")
g=d.box("③ 고치기는 Git 에서\ngit revert → git push\n(kubectl 로 고치면 자동 치유가 되돌림)",870,270,280,90,OK+"fontStyle=1;")
d.edge(f,g,"")
for x in (b1,b2,b3,b4): pass
d.edge(b2,f,"","dashed=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
d.text("Argo CD 자체가 고장이면: kubectl -n argocd get pods → 부품 로그 (repo-server · application-controller)",20,470,1130,30,"fontStyle=2;")
d.save(P+"04-diagnosis.drawio")
