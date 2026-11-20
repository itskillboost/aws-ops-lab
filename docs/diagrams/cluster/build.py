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


P="docs/diagrams/cluster/"
# ① 오늘 직접 만드는 것
d=D("1. 오늘 직접 만드는 클러스터")
me=d.box("나\n(CloudShell)\naws · kubectl",20,120,140,80,GRAY+"fontStyle=1;")
d.group("AWS 계정 · 서울 리전",190,20,1030,720,"fillColor=#FFFFFF;strokeColor=#232F3E;")
env=d.box("아침 배포(start.sh cluster)\nL1 네트워크 + 주변 구성\n· 클러스터 역할 ctl-role\n· 노드 역할 worker-role\n· 노드 시작 템플릿(태그·IMDS 홉 2)",210,55,250,120,NOTE)
d.group("① EKS 컨트롤 플레인 — 관제탑 (AWS가 대신 운영)",480,55,720,150,CP)
api=d.box("API 서버",500,95,150,50,"fillColor=#FFFFFF;strokeColor=#D79B00;fontStyle=1;")
d.box("스케줄러 · 컨트롤러\n· etcd",670,95,170,50,"fillColor=#FFFFFF;strokeColor=#D79B00;")
auth=d.box("인증(authenticator)\n접근 항목 확인",860,95,170,50,"fillColor=#FFFFFF;strokeColor=#D79B00;")
d.text("인증 모드 API · 접근 항목(Access Entry)",660,155,500,30,"fontStyle=2;")
cw=d.group("CloudWatch",1040,230,160,330,"fillColor=#FCE4EC;strokeColor=#C2185B;")
lg=d.box("② 컨트롤 플레인 로그\n/aws/eks/…/cluster\napi · audit ·\nauthenticator ·\ncontrollerManager ·\nscheduler",1050,270,140,140,"fillColor=#FFFFFF;strokeColor=#C2185B;")
ci=d.box("④ Container Insights\n지표 · 로그",1050,440,140,90,"fillColor=#FFFFFF;strokeColor=#C2185B;")
d.group("VPC (L1) · 프라이빗 서브넷 2개(AZ-a · AZ-c)",210,230,810,490,VPC)
d.group("③ 관리형 노드 그룹 s00-cluster-ng · EC2 m6i.large ×2 (시작 템플릿 적용)",230,265,770,250,NODE)
n1=d.box("노드 1\nkubelet(현장 반장) · containerd(작업자)\nCloudWatch 에이전트 · 노드 모니터링 에이전트",250,305,360,90,SYS)
n2=d.box("노드 2\nkubelet · containerd\nCloudWatch 에이전트 · 노드 모니터링 에이전트",630,305,350,90,SYS)
d.text("노드 역할 worker-role 로 관제탑에 \"나 노드요\"라고 인증한다(접근 항목 유형 EC2_LINUX)",250,410,730,30,"fontStyle=2;")
d.group("⑤ 주변 구성(extras/setup.sh)",230,535,770,165,OK)
d.box("접근 항목\n강사 읽기 전용 · FIS",250,575,170,70,"fillColor=#FFFFFF;strokeColor=#82B366;")
d.box("OIDC 공급자\n(IRSA 신원 창구)",435,575,150,70,"fillColor=#FFFFFF;strokeColor=#82B366;")
d.box("관리형 애드온\nCNI · CoreDNS ·\nEBS CSI …",600,575,150,70,"fillColor=#FFFFFF;strokeColor=#82B366;")
d.box("진단 대상\nHeadlamp · 샘플 앱 ·\nPostgreSQL · Redis",765,575,215,70,"fillColor=#FFFFFF;strokeColor=#82B366;")
d.text("번호 = 오늘 따라하기 순서 (①클러스터 → ②로그 → ③노드 그룹 → ④Container Insights → ⑤주변 구성)",250,655,740,30,"fontStyle=1;fontColor=#333333;")
d.edge(me,api,"aws eks create-cluster","exitX=1;exitY=0.85;entryX=0.2;entryY=1;",points=[(180,218),(530,218)])
d.edge(env,api,"역할 고르기","dashed=1;exitX=1;exitY=0.3;entryX=0;entryY=0.5;")
d.edge(api,lg,"","exitX=1;exitY=0.5;entryX=0.5;entryY=0;",points=[(1120,120)])
d.edge(n1,api,"상태 보고(10초)","exitX=0.5;exitY=0;entryX=0.5;entryY=1;")
d.edge(n2,ci,"지표","dashed=1;exitX=1;exitY=0.75;entryX=0;entryY=0.5;",points=[(1010,375),(1010,485)])
d.save(P+"01-build.drawio")

# ② 노드의 건강 — 상태 보고와 조건
d=D("2. 노드의 건강")
d.group("관제탑(컨트롤 플레인)",620,20,420,250,CP)
nc=d.box("노드 컨트롤러\n\"40초 동안 보고가 없으면\nReady=Unknown(NotReady)\"\n\"5분 지나면 파드를 다른 노드로\"",640,60,380,110,"fillColor=#FFFFFF;strokeColor=#D79B00;")
st=d.box("노드 상태(Conditions)\nReady · MemoryPressure ·\nDiskPressure · PIDPressure",640,185,380,70,"fillColor=#FFFFFF;strokeColor=#D79B00;")
d.group("노드(EC2) 안",20,20,560,560,NODE)
kl=d.box("kubelet (현장 반장)\n· 10초마다 \"살아 있음\" 보고(Lease)\n· 자원 감시 → 압박이면 조건 True + 파드 축출\n· 로그: journalctl -u kubelet",40,60,520,110,SYS+"fontStyle=1;")
cr=d.box("containerd (작업자)\n· 컨테이너 실행\n· 로그: journalctl -u containerd",40,195,520,80,SYS)
d.box("systemd — 두 서비스를 켜고 끈다\nsystemctl status kubelet containerd",40,300,520,60,GRAY)
d.group("축출 기준(실습 노드 설정)",40,380,520,180,NOTE)
d.box("메모리   memory.available < 500Mi  → MemoryPressure\n디스크   nodefs.available < 10%     → DiskPressure\nPID      pid.available < 25%         → PIDPressure\n(실습 노드는 프로세스 한도 pid_max=8192)",55,415,490,120,"fillColor=#FFFFFF;strokeColor=#D6B656;align=left;spacingLeft=10;fontFamily=Courier New;")
d.edge(kl,nc,"Lease 갱신","exitX=1;exitY=0.3;entryX=0;entryY=0.5;")
d.edge(kl,st,"조건 보고","exitX=1;exitY=0.8;entryX=0;entryY=0.5;")
d.edge(kl,cr,"컨테이너 띄워라","exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
d.group("NotReady 의 세 갈래(cluster-1 · cluster-3)",620,300,420,280,BAD)
d.box("kubelet 이 멈췄다 → 보고 자체가 끊김\n(Ready=Unknown, \"Kubelet stopped posting\")",635,340,390,65,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("containerd 가 멈췄다 → kubelet 은 살아\n\"런타임이 안 된다\"고 보고",635,415,390,65,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("관제탑이 노드를 거절한다(인증 실패)\n→ kubelet 은 살아 있지만 보고가 거부됨",635,490,390,65,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.save(P+"02-node-health.drawio")

# ③ 컨트롤 플레인 로그 — 무엇을 어디서 보나
d=D("3. 컨트롤 플레인 로그")
d.group("EKS 관제탑",20,20,330,420,CP)
t=[("api","API 서버 동작·요청 처리"),("audit","누가·언제·무엇을 바꿨나(감사)"),("authenticator","IAM 신원 → 클러스터 사용자 변환·거절"),("controllerManager","컨트롤러 동작(노드 수명 등)"),("scheduler","파드 배치 결정·실패 이유")]
ys=[]
for i,(k,v) in enumerate(t):
    ys.append(d.box(k+"\n"+v,40,60+i*74,290,62,"fillColor=#FFFFFF;strokeColor=#D79B00;"+("fontStyle=1;" if k in("audit","authenticator") else "")))
lgg=d.box("CloudWatch Logs\n로그 그룹 /aws/eks/<클러스터>/cluster\n로그 스트림: kube-apiserver-audit-… ·\nauthenticator-… · kube-scheduler-…",420,60,360,110,"fillColor=#FCE4EC;strokeColor=#C2185B;fontStyle=1;")
q=d.box("Logs Insights 로 묻기(예)\n① 누가 노드를 cordon 했나\nfilter objectRef.resource=\"nodes\" and verb=\"patch\"\n② 노드가 왜 거절됐나\nfilter @logStream like /authenticator/ and @message like /denied|not found/",420,215,520,150,NOTE+"align=left;spacingLeft=10;")
for y in ys: d.edge(y,lgg,"","exitX=1;exitY=0.5;entryX=0;entryY=0.5;strokeWidth=1;")
d.edge(lgg,q,"질의","exitX=0.5;exitY=1;entryX=0.2;entryY=0;")
d.text("로그는 켜야 쌓인다(구축 2). 켜기 전의 일은 찾을 수 없다 — 그래서 구축 첫날 켠다.",420,390,560,30,"fontStyle=1;fontColor=#B85450;")
d.save(P+"03-control-plane-logs.drawio")

# ④ 진단 순서
d=D("4. 노드 장애 진단 순서")
s=d.box("kubectl get nodes\n(STATUS 열)",20,40,200,60,NOTE+"fontStyle=1;")
a=d.box("NotReady",280,20,200,45,BAD+"fontStyle=1;")
b=d.box("Ready 인데 파드가 쫓겨남\n(Evicted · Pending)",280,90,200,55,BAD+"fontStyle=1;")
c=d.box("Ready,SchedulingDisabled",280,165,200,45,BAD+"fontStyle=1;")
d.edge(s,a,""); d.edge(s,b,""); d.edge(s,c,"","exitX=0.5;exitY=1;entryX=0;entryY=0.5;",points=[(120,187)])
a1=d.box("② describe node\nConditions 의 Ready 사유·메시지\n(Kubelet stopped posting / runtime down)",540,10,290,70,GRAY)
a2=d.box("③ 노드 안: Session Manager\nsystemctl status kubelet containerd\njournalctl -u kubelet -n 50",870,10,290,70,SYS)
a3=d.box("④ kubelet 은 살아 있는데 Unauthorized?\n→ authenticator 로그 · 접근 항목 목록",870,95,290,60,NOTE)
d.edge(a,a1,""); d.edge(a1,a2,""); d.edge(a2,a3,"","dashed=1;")
b1=d.box("② describe node\nConditions(Memory·Disk·PID Pressure)\nTaints(node.kubernetes.io/…-pressure)",540,170,290,75,GRAY)
b2=d.box("③ 이벤트를 시간순으로\nget events -A --sort-by=.lastTimestamp\n(Evicted · NodeHasDiskPressure …)",870,170,290,75,GRAY)
b3=d.box("④ 범인 찾기\n메모리: kubectl top pods\n디스크: df -h / du · PID: ps -eLf | wc -l",870,260,290,75,SYS)
d.edge(b,b1,"","exitX=1;exitY=0.8;entryX=0;entryY=0.5;",points=[(510,130),(510,207)]); d.edge(b1,b2,""); d.edge(b2,b3,"")
c1=d.box("② 누가 했나 — audit 로그\nverb=patch · resource=nodes\n· user.username",540,350,290,70,NOTE)
c2=d.box("③ 의도 확인 후 uncordon\n권한 정리(누가 노드를 바꿀 수 있나)",870,350,290,70,OK)
d.edge(c,c1,"","exitX=0.5;exitY=1;entryX=0;entryY=0.5;",points=[(380,385)]); d.edge(c1,c2,"")
d.text("공통: 장애 전후로 무엇이 바뀌었나(CloudTrail · audit · SSM Run Command 기록)를 보는 것도 정당한 진단이다",20,450,1140,30,"fontStyle=2;")
d.save(P+"04-diagnosis.drawio")
