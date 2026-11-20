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



P="docs/diagrams/podnet/"
# ① 오늘 환경의 아키텍처
d=D("1. 오늘 만드는 정문과 통로")
u=d.box("사용자\n(브라우저 · 부하 파드)",20,115,150,70,GRAY+"fontStyle=1;")
d.group("AWS 계정 · 서울 리전",200,20,1000,700,"fillColor=#FFFFFF;strokeColor=#232F3E;")
d.group("VPC (L1)",220,55,960,645,VPC)
d.group("퍼블릭 서브넷 ×2 (태그 kubernetes.io/role/elb)",240,90,920,110,SUB)
alb=d.box("② ALB (정문)\n리스너 :80 → 타깃 그룹(파드 IP:8080) · 건강검진 /health",520,120,420,60,AWS+"fontStyle=1;")
d.group("프라이빗(앱) 서브넷 ×2 · 파드도 이 서브넷 IP",240,220,920,460,SUB)
d.group("EKS 노드 2대 (클러스터 보안 그룹)",260,255,880,405,NODE)
lbc=d.box("① Load Balancer Controller\n(대행사, kube-system)\nIRSA 로 IAM 역할을 빌려\nALB·타깃 그룹을 만든다",280,290,250,100,SYS+"fontStyle=1;")
a1=d.box("앱 파드\n10.0.10.x:8080",590,310,170,55,POD)
a2=d.box("앱 파드\n10.0.11.x:8080",780,310,170,55,POD)
db=d.box("PostgreSQL\n· Redis",970,310,150,55,POD)
dns=d.box("CoreDNS (전화번호부)\n\"postgres\" → 172.20.x.x",280,420,250,60,SYS)
ing=d.box("③ Ingress opslab-app\n(정문 안내 데스크)",590,420,200,60,"fillColor=#E1D5E7;strokeColor=#9673A6;fontStyle=1;")
svc=d.box("Service opslab-app (대표 전화번호)\n셀렉터 → Endpoints(파드 IP 목록)",820,420,300,60,"fillColor=#E1D5E7;strokeColor=#9673A6;")
cni=d.box("VPC CNI (aws-node)\n파드 IP 배분 · 정책 적용",280,520,250,60,SYS)
np=d.box("④ NetworkPolicy db-allow-app (출입문 규칙)\nDB 에는 앱 파드만 — VPC CNI 네트워크 정책 기능이 적용",590,520,530,60,"fillColor=#E1D5E7;strokeColor=#9673A6;")
iam=d.box("IAM 역할\ns00-podnet-lbc-role\n(권한 경계)\n← OIDC 공급자",20,290,160,100,AWS)
d.edge(u,alb,"http://ALB 주소","exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
d.text("파드 IP 로 직접(target-type ip)",880,262,230,20,"fontSize=12;")
d.edge(alb,a1,"","exitX=0.36;exitY=1;entryX=0.5;entryY=0;")
d.edge(alb,a2,"","exitX=0.83;exitY=1;entryX=0.5;entryY=0;")
d.edge(lbc,alb,"만든다·고친다","dashed=1;exitX=0.5;exitY=0;entryX=0;entryY=0.8;",points=[(405,168)])
d.edge(lbc,ing,"지켜본다","dashed=1;exitX=1;exitY=0.85;entryX=0;entryY=0.5;",points=[(560,375),(560,450)])
d.edge(ing,svc,"백엔드","exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
d.edge(svc,a2,"Endpoints","dashed=1;exitX=0.2;exitY=0;entryX=0.7;entryY=1;")
d.edge(a2,db,"5432·6379","exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
d.edge(iam,lbc,"IRSA","dashed=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
d.text("번호 = 오늘 따라하기 순서(구축 1 IRSA·① Load Balancer Controller(구축 2) → ③ Ingress(구축 3) → ④ 네트워크 정책(구축 4))",260,615,880,25,"fontStyle=1;")
d.save(P+"01-architecture.drawio")

# ② 요청 한 건의 여행
d=D("2. 요청 한 건의 여행")
steps=[("① DNS","ALB 주소 → 공인 IP"),("② ALB 리스너 :80","규칙 / → 타깃 그룹"),("③ 타깃 그룹","healthy 인 파드 IP 만 골라 보낸다\n(건강검진 /health)"),("④ 보안 그룹","ALB → 파드 8080 허용(클러스터 보안 그룹)"),("⑤ NetworkPolicy","파드로 들어오는 통신 허용?"),("⑥ 앱 컨테이너 :8080","/api 응답, /db·/cache 는 DB·Redis 로"),("⑦ CoreDNS","\"postgres\" 이름 → Service IP"),("⑧ DB 접속","NetworkPolicy·보안 그룹이 5432 허용?")]
ids=[]
for i,(t,v) in enumerate(steps):
    x=20+(i%4)*290; y=40 if i<4 else 230
    ids.append(d.box(t+"\n"+v,x,y,260,100,(AWS if i<4 else (SYS if i in(4,6) else POD))+"fontStyle=1;" if i!=5 else POD))
for i in range(3): d.edge(ids[i],ids[i+1],"")
d.edge(ids[3],ids[4],"","exitX=0.5;exitY=1;entryX=0.5;entryY=0;",points=[(1040,190),(150,190)])
for i in range(4,7): d.edge(ids[i],ids[i+1],"")
d.group("어디가 끊기면 무엇이 보이나",20,370,1130,200,NOTE)
d.box("②③ 타깃 0개 · 전부 unhealthy\n→ ALB 503 · 502\n(Endpoints 비었나? targetPort?)",40,410,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("④ 보안 그룹이 막음\n→ 타깃 Timeout · ALB 504\n(Reason: Target.Timeout)",320,410,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("⑦ DNS 실패\n→ 앱 500 · 새 파드 init 대기\n(nslookup 실패, CoreDNS 0개·오류)",600,410,260,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("⑤⑧ 정책·SG 차단\n→ /db 만 500, /api 는 200\n(라벨·포트·출발지 확인)",880,410,250,130,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.save(P+"02-request-path.drawio")

# ③ 파드 IP 는 어디서 오나 (VPC CNI)
d=D("3. 파드 IP 는 어디서 오나")
d.group("앱 서브넷 10.0.10.0/24 — 남은 IP(AvailableIpAddressCount)",20,20,700,360,SUB)
d.group("노드(EC2 m6i.large) — ENI 최대 3개 × IP 10개",40,60,480,300,NODE)
e1=d.box("ENI 1(기본)\nIP 10개 — 사용 중 파드에 배분",60,100,200,80,SYS)
e2=d.box("ENI 2(웜 풀)\n미리 받아 둔 여분 IP",290,100,200,80,OK)
e3=d.box("ENI 3\n필요할 때 더 붙인다\n(MAX_ENI 가 막으면 못 붙임)",60,210,200,90,GRAY)
ip=d.box("ipamd(aws-node)\n파드가 뜰 때 IP 를 하나 준다\n여분이 모자라면 ENI·IP 를 더 받는다",290,210,210,110,SYS+"fontStyle=1;")
d.box("다른 팀 ENI · 노드 · LB 가\n서브넷 IP 를 쓰고 있다",540,120,160,80,GRAY)
d.group("IP 를 못 받으면",760,20,400,360,BAD)
d.box("파드: ContainerCreating 에서 멈춤\n이벤트: FailedCreatePodSandBox\n\"failed to assign an IP address\"",780,60,360,90,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("확인: 서브넷 남은 IP\naws ec2 describe-subnets\n노드 ENI·aws-node 설정(MAX_ENI 등)",780,170,360,90,"fillColor=#FFFFFF;strokeColor=#B85450;")
d.box("대책: 남는 ENI 정리 · 서브넷 추가\n· 접두사 위임(prefix delegation)",780,280,360,80,OK)
d.edge(ip,e2,"여분에서 배분","exitX=0.5;exitY=0;entryX=0.5;entryY=1;")
d.edge(ip,e3,"모자라면","dashed=1;exitX=0;exitY=0.5;entryX=1;entryY=0.5;")
d.save(P+"03-vpc-cni-ip.drawio")

# ④ 진단 순서
d=D("4. 네트워크 장애 진단 순서")
s=d.box("증상부터\n(사용자 응답 코드 · 파드 상태)",20,135,200,80,NOTE+"fontStyle=1;")
a=d.box("새 파드 ContainerCreating",280,20,230,50,BAD+"fontStyle=1;")
b=d.box("ALB 503 · 502 · 504",280,150,230,50,BAD+"fontStyle=1;")
c=d.box("/api 는 되고 /db·/cache 만 500\n또는 새 파드 init 대기",280,290,230,70,BAD+"fontStyle=1;")
d.edge(s,a,"","exitX=1;exitY=0.25;entryX=0;entryY=0.5;",points=[(250,155),(250,45)]); d.edge(s,b,"","exitX=1;exitY=0.5;entryX=0;entryY=0.5;"); d.edge(s,c,"","exitX=1;exitY=0.75;entryX=0;entryY=0.5;",points=[(250,195),(250,325)])
a1=d.box("describe pod 이벤트\n\"failed to assign an IP\"\n→ 서브넷 남은 IP · aws-node 설정",560,10,300,75,GRAY)
d.edge(a,a1,"")
b1=d.box("① get ingress · describe ingress(Events)\n② get svc,endpoints — 비었나? 포트?\n③ get pods --show-labels",560,135,300,85,GRAY)
b2=d.box("④ describe-target-health\nReason: ResponseCodeMismatch(경로)\n· Timeout(보안 그룹) · 타깃 없음",890,135,290,85,SYS)
d.edge(b,b1,""); d.edge(b1,b2,"")
c1=d.box("① 파드 안 이름 풀기\nnslookup postgres → 실패면 CoreDNS\n(get deploy coredns · logs · Corefile)",560,275,300,85,GRAY)
c2=d.box("② 이름은 풀리는데 접속 실패\nget networkpolicy(라벨·포트·Egress 53)\n· 파드 보안 그룹 · 클러스터 SG",890,275,290,85,SYS)
d.edge(c,c1,""); d.edge(c1,c2,"이름 OK","dashed=1;")
d.text("공통: 무엇이 바뀌었나 — audit 로그(쿠버네티스 변경) · CloudTrail(보안 그룹·ENI 변경)",20,400,1160,30,"fontStyle=2;")
d.save(P+"04-diagnosis.drawio")
