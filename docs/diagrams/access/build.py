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




P="docs/diagrams/access/"
SVC="fillColor=#E1D5E7;strokeColor=#9673A6;"
# ① 오늘 환경의 아키텍처
d=D("1. 오늘 만드는 권한과 금고")
d.group("EKS 클러스터",20,20,760,560,NODE)
d.group("app 네임스페이스",40,55,470,300,"fillColor=#FFFFFF;strokeColor=#2F6FB3;")
d.group("앱 파드 (2개)",60,90,430,170,"fillColor=#EEF4FF;strokeColor=#326CE5;")
ini=d.box("vault-agent-init\n(출근 전 금고에서\n비밀 꺼내 오기)",75,125,130,75,SYS)
app=d.box("app 컨테이너\n/etc/app/db-cred.env 읽기\n/aws → STS",215,125,140,75,POD)
side=d.box("vault-agent\n(사이드카,\n비밀 갱신)",365,125,110,75,SYS)
sa=d.box("서비스 계정 opslab-app\n① 어노테이션: role-arn = s01-access-app-role",60,280,430,50,SVC+"fontStyle=1;")
d.group("vault 네임스페이스",530,55,230,300,"fillColor=#FFFFFF;strokeColor=#2F6FB3;")
v0=d.box("② vault-0 (금고)\nKV secret/opslab/db\n정책 · Kubernetes Auth\n파일 저장소(PVC)",545,90,200,110,"fillColor=#FFE6CC;strokeColor=#D79B00;fontStyle=1;")
inj=d.box("Agent Injector\n(사이드카 주입기)",545,215,200,50,SYS)
cj=d.box("vault-unsealer CronJob\n1분마다 봉인 확인",545,280,200,55,SYS)
d.group("RBAC",40,375,720,190,"fillColor=#FFFFFF;strokeColor=#9673A6;")
ae=d.box("접근 항목(Access Entry)\n\"이 IAM 역할은 들어와도 된다\"\n→ 쿠버네티스 그룹 opslab-dev",60,410,260,80,SVC+"fontStyle=1;")
rb=d.box("RoleBinding dev\n그룹 opslab-dev ↔ Role dev",350,410,180,80,SVC)
ro=d.box("Role dev\n보기 · 로그 · 재시작만\n(app 네임스페이스)",560,410,180,80,SVC+"fontStyle=1;")
d.text("접근 항목 = 들어올 수 있나 / RBAC = 들어와서 무엇을 할 수 있나",60,515,680,30,"fontStyle=2;")
d.group("AWS",810,20,370,560,AWS)
r1=d.box("IAM 역할 s01-access-app-role\n(권한 경계)",830,60,330,55,AWS+"fontStyle=1;")
oidc=d.box("OIDC 공급자\n(파드 신원 확인 창구)",830,135,330,50,AWS)
sts=d.box("STS\nAssumeRoleWithWebIdentity",830,205,330,50,AWS)
sm=d.box("Secrets Manager\ns01-access-vault-init\n(봉인 해제 열쇠·루트 토큰)",830,275,330,65,AWS)
r2=d.box("IAM 역할 s01-access-unsealer-role\n(CronJob 용 IRSA)",830,355,330,50,AWS)
r3=d.box("IAM 역할 s01-access-dev-role\n(개발자가 빌려 쓰는 역할)",830,430,330,55,AWS+"fontStyle=1;")
d.edge(ini,app,"",""); d.edge(sa,app,"토큰","dashed=1;exitX=0.5;exitY=0;entryX=0.5;entryY=1;")
d.edge(app,sts,"①-④ IRSA","dashed=1;exitX=0.5;exitY=0;entryX=0;entryY=0.5;",points=[(285,40),(800,40),(800,230)])
d.edge(side,v0,"③ 로그인·읽기","exitX=0.5;exitY=0;entryX=0;entryY=0.2;",points=[(420,75),(515,75),(515,112)])
d.edge(inj,side,"주입","dashed=1;exitX=0;exitY=0.5;entryX=1;entryY=0.5;",points=[(520,240),(520,162)])
d.edge(cj,sm,"열쇠 읽기(IRSA)","dashed=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
d.edge(r3,ae,"⑤ 빌려서 접속","exitX=0;exitY=0.5;entryX=0.5;entryY=1;",points=[(790,457),(790,505),(190,505)])
d.edge(ae,rb,""); d.edge(rb,ro,"")
d.save(P+"01-architecture.drawio")

# ② IRSA — 파드가 IAM 역할을 빌리는 길
d=D("2. IRSA 로 역할을 빌리는 길")
st=[("① 서비스 계정 어노테이션","eks.amazonaws.com/role-arn\n= 빌릴 역할의 ARN"),("② 파드가 뜰 때","주입기가 env AWS_ROLE_ARN·\nAWS_WEB_IDENTITY_\nTOKEN_FILE 과 토큰 파일을 넣는다"),("③ 앱 → STS","AssumeRoleWithWebIdentity\n(역할 ARN + 토큰)"),("④ STS 의 확인","OIDC 공급자로 토큰 서명 확인\n신뢰 정책의 aud·sub 와 비교"),("⑤ 임시 자격증명","1시간짜리 키 → /aws 가\nassumed-role/<역할> 표시")]
ids=[]
for i,(t,v) in enumerate(st):
    ids.append(d.box(t+"\n"+v,20+i*232,40,212,110,(SVC if i<2 else AWS)+"fontStyle=1;"))
for i in range(4): d.edge(ids[i],ids[i+1],"")
d.group("어디가 틀리면 무엇이 보이나 (/aws 응답 · 앱 로그)",20,190,1140,200,NOTE)
d.box("① 역할 ARN 오타\n→ AccessDenied: Not authorized to\nperform sts:AssumeRoleWithWebIdentity\n(역할이 없음)",40,230,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("④ 신뢰 정책 sub 불일치\n→ 같은 AccessDenied\n(역할은 있으나 이 서비스 계정은 불허)\n신뢰 정책의 네임스페이스:이름 확인",320,230,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("④ OIDC 공급자 없음\n→ InvalidIdentityToken:\nNo OpenIDConnect provider found",600,230,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("확인 순서\n어노테이션 → 파드 env(AWS_*)\n→ 신뢰 정책(aud·sub) → OIDC 공급자",880,230,260,130,OK+"fontStyle=1;")
d.save(P+"02-irsa.drawio")

# ③ Vault Agent 주입과 Kubernetes Auth
d=D("3. 금고에서 비밀을 꺼내 오는 길")
st=[("① 주입","Agent Injector 가 파드에\ninit·사이드카를 붙인다\n(어노테이션 agent-inject)"),("② 로그인","vault-agent-init 이 서비스 계정\n토큰을 내밀고\nauth/kubernetes/login (역할 opslab-app)"),("③ 토큰 검사","Vault → 쿠버네티스 API\nTokenReview\n(system:auth-delegator 권한)"),("④ 역할 조건","Auth 역할의 허용\n서비스 계정·네임스페이스와 비교\n→ 정책 opslab-app 이 붙은 토큰"),("⑤ 비밀 읽기·파일","정책이 허용하면 secret/opslab/db\n→ /etc/app/db-cred.env\n앱이 DB 비밀번호로 사용")]
ids=[]
for i,(t,v) in enumerate(st):
    ids.append(d.box(t+"\n"+v,20+i*232,40,212,120,("fillColor=#FFE6CC;strokeColor=#D79B00;" if i in (2,3,4) else SYS)+"fontStyle=1;"))
for i in range(4): d.edge(ids[i],ids[i+1],"")
d.group("어디가 틀리면 무엇이 보이나 (kubectl logs <파드> -c vault-agent-init)",20,200,1140,200,NOTE)
d.box("① 주입기 0개·어노테이션 없음\n→ 사이드카 없이 뜸 → 비밀번호 파일 없음\n→ 앱 CrashLoopBackOff",40,240,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("②③ 로그인 실패\npermission denied · connection refused\n· tokenreviews forbidden\n→ 파드 Init:0/2 에서 정지",320,240,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("④ 네임스페이스·이름 불일치\n\"namespace not authorized\"\n→ Init 에서 정지",600,240,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("⑤ 경로 오타·정책 없음\n403 permission denied · 비밀 없음\n→ Init 에서 계속 기다림",880,240,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.text("봉인(sealed)된 Vault 는 모든 요청을 거절한다 — 먼저 vault status 와 vault-unsealer CronJob 을 본다",20,420,1140,30,"fontStyle=2;")
d.save(P+"03-vault-inject.drawio")

# ④ 진단 순서
d=D("4. 권한·시크릿 장애 진단 순서")
s=d.box("증상부터",20,150,160,70,NOTE+"fontStyle=1;")
a=d.box("앱이 AWS API 실패\n(/aws 500, AccessDenied)",240,20,250,65,BAD+"fontStyle=1;")
b=d.box("새 파드가 Init 에서 멈춤\n또는 CrashLoopBackOff",240,152,250,65,BAD+"fontStyle=1;")
c=d.box("사람이 kubectl 하면 Forbidden",240,290,250,55,BAD+"fontStyle=1;")
d.edge(s,a,"","exitX=1;exitY=0.25;entryX=0;entryY=0.5;",points=[(210,167),(210,52)]); d.edge(s,b,"","exitX=1;exitY=0.5;entryX=0;entryY=0.5;"); d.edge(s,c,"","exitX=1;exitY=0.75;entryX=0;entryY=0.5;",points=[(210,202),(210,317)])
a1=d.box("파드 env AWS_ROLE_ARN\n→ 서비스 계정 어노테이션\n→ 신뢰 정책 aud·sub → OIDC 공급자",540,10,320,85,GRAY)
d.edge(a,a1,"")
b1=d.box("① 사이드카가 붙었나?\n(get pod -o jsonpath 컨테이너 이름)\n없으면 Injector·어노테이션",540,140,320,85,GRAY)
b2=d.box("② logs -c vault-agent-init\n로그인 실패 → Auth 역할·설정\n·auth-delegator\n읽기 실패 → 정책·경로 · vault status",930,135,250,95,"fillColor=#FFE6CC;strokeColor=#D79B00;")
d.edge(b,b1,""); d.edge(b1,b2,"","dashed=1;"); d.text("붙어 있음",868,155,60,20,"fontSize=11;")
c1=d.box("kubectl auth can-i … --as-group\n→ Role 동사 → RoleBinding 대상\n→ 접근 항목의 그룹",540,280,320,85,GRAY)
d.edge(c,c1,"")
d.text("공통: 무엇이 바뀌었나 — audit 로그(쿠버네티스 변경) · CloudTrail(IAM·EKS 접근 항목 변경)",20,400,1160,30,"fontStyle=2;")
d.save(P+"04-diagnosis.drawio")
