# Day 1 이론 강의용 draw.io 다이어그램 생성기 — 기본 도형만 사용(어디서 열어도 동일하게 보이도록)
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

# ① 클러스터 구조
d=D("1. 클러스터 구조")
me=d.box("나\n(CloudShell)\nkubectl · helm",20,95,140,80,GRAY+"fontStyle=1;")
pc=d.box("내 PC 브라우저\nHeadlamp 화면\n(토큰 로그인)",20,225,140,70,GRAY)
d.group("AWS 계정 · 서울 리전(ap-northeast-2)",190,20,1010,700,"fillColor=#FFFFFF;strokeColor=#232F3E;")
d.group("EKS 컨트롤 플레인 — 관제탑 (AWS가 대신 운영)",210,60,960,110,CP)
api=d.box("API 서버\n(주문 접수 창구)",230,95,200,60,"fillColor=#FFFFFF;strokeColor=#D79B00;fontStyle=1;")
d.box("etcd\n(주문 기록부)",450,95,160,60,"fillColor=#FFFFFF;strokeColor=#D79B00;")
d.box("스케줄러\n(자리 배정)",630,95,160,60,"fillColor=#FFFFFF;strokeColor=#D79B00;")
d.box("컨트롤러 매니저\n(원하는 상태 맞추기)",810,95,200,60,"fillColor=#FFFFFF;strokeColor=#D79B00;")
d.group("VPC (L1 층) — 노드와 로드밸런서가 사는 네트워크",210,190,960,510,VPC)
d.group("퍼블릭 서브넷",230,215,920,85,SUB)
nlb=d.box("NLB (Headlamp 출입문)\n내 PC IP만 허용",470,240,210,50,"fillColor=#FFFFFF;strokeColor=#8C4FFF;")
d.box("NAT 게이트웨이\n(노드의 인터넷 출구)",940,240,190,50,"fillColor=#FFFFFF;strokeColor=#8C4FFF;")
d.group("노드 1 · EC2 m6i.large · AZ-a (프라이빗 서브넷)",230,310,450,330,NODE)
kl1=d.box("kubelet (현장 반장)",250,345,200,40,SYS+"fontStyle=1;")
d.box("containerd (작업자)",460,345,200,40,SYS)
a1=d.box("파드: opslab-app",250,410,190,50,POD)
hl=d.box("파드: headlamp",460,410,200,50,POD)
pg=d.box("파드: postgres-0",250,485,190,50,POD)
ebs=d.box("EBS gp3 볼륨\n(PostgreSQL 디스크)",460,480,200,60,"shape=cylinder3;boundedLbl=1;size=8;fillColor=#E1D5E7;strokeColor=#9673A6;")
d.box("kube-system 파드\n(aws-node · kube-proxy · CoreDNS · EBS CSI · Container Insights …)",250,565,410,55,"fillColor=#FFFFFF;strokeColor=#6C8EBF;dashed=1;")
d.group("노드 2 · EC2 m6i.large · AZ-b (프라이빗 서브넷)",700,310,450,330,NODE)
kl2=d.box("kubelet (현장 반장)",720,345,200,40,SYS+"fontStyle=1;")
d.box("containerd (작업자)",930,345,200,40,SYS)
a2=d.box("파드: opslab-app",720,410,190,50,POD)
d.box("파드: redis",930,410,200,50,POD)
ld=d.box("파드: opslab-load\n(초당 10건 부하)",720,485,190,50,POD)
d.box("kube-system 파드",720,565,410,55,"fillColor=#FFFFFF;strokeColor=#6C8EBF;dashed=1;")
d.text("app 네임스페이스(라벨 course=opslab): opslab-app ×2 · postgres · redis · opslab-load    ·    headlamp 네임스페이스: headlamp",250,652,900,30,"fontStyle=2;fontColor=#333333;")
d.edge(me,api,"주문서 제출(HTTPS)")
d.edge(api,kl1,"이 파드 맡아","exitX=0.2;exitY=1;entryX=0.2;entryY=0;")
d.edge(api,kl2,"이 파드 맡아","exitX=1;exitY=0.75;entryX=0.2;entryY=0;",points=[(760,180)])
d.edge(pc,nlb,"")
d.edge(nlb,hl,"","dashed=1;exitX=0.95;exitY=1;entryX=1;entryY=0.5;",points=[(670,435)])
d.edge(ld,a2,"Service","dashed=1;")
d.edge(a1,pg,"DB 조회","dashed=1;")
d.edge(pg,ebs,"","dashed=1;endArrow=none;")
d.save("docs/diagrams/workload/01-cluster.drawio")

# ② 파드의 일생
d=D("2. 파드의 일생")
steps=[("① 노드 고르기","스케줄러","Pending\n(NODE <none>)","workload-1","이벤트 FailedScheduling"),
       ("② 이미지 받기","kubelet","ErrImagePull →\nImagePullBackOff","workload-5","이벤트 Failed to pull image"),
       ("③ init 실행·종료","kubelet","Init:0/1 · Init:Error\nInit:ImagePullBackOff","workload-6","logs -c wait-db"),
       ("④ 앱 시작","kubelet","CrashLoopBackOff\n(Exit Code 1)","workload-2","Last State → logs --previous"),
       ("⑤ 실행 중 메모리","리눅스 커널","OOMKilled\n(Exit Code 137)","workload-3","Limits · kubectl top"),
       ("⑥ 건강검진 반복","kubelet","Running인데\nRESTARTS↑ / READY 0/1","workload-4","probe 이벤트 · 설정")]
d.box("주문서\n(Deployment)",10,40,120,70,GRAY+"fontStyle=1;")
prev="c1"; x=160
for t,who,st,lab,look in steps:
    s_=d.box(f"{t}\n담당: {who}",x,40,170,70,OK+"fontStyle=1;")
    d.edge(prev,s_)
    b=d.box(f"막히면\n{st}",x,150,170,70,BAD)
    d.edge(s_,b,"","dashed=1;strokeColor=#B85450;")
    d.box(lab,x,235,170,28,"fillColor=#326CE5;fontColor=#fff;strokeColor=none;fontStyle=1;")
    d.box("먼저 볼 곳:\n"+look,x,275,170,55,NOTE)
    prev=s_; x+=195
ok=d.box("정상 서비스 ✔",x,40,120,70,"fillColor=#82B366;fontColor=#fff;strokeColor=none;fontStyle=1;")
d.edge(prev,ok)
d.text("STATUS 한 단어가 '어느 단계에서 막혔는지'를 알려 준다 → 그 단계의 '먼저 볼 곳'부터 확인",10,345,1100,30,"fontStyle=1;fontSize=14;")
d.save("docs/diagrams/workload/02-pod-lifecycle.drawio")

# ③ 롤링 업데이트가 막힐 때
d=D("3. 롤링 업데이트가 막힐 때")
dep=d.box("Deployment opslab-app\n희망 2개 · maxSurge 1 · maxUnavailable 0",20,140,240,80,GRAY+"fontStyle=1;")
old=d.group("옛 ReplicaSet (지금 템플릿 이전 것)",320,30,420,140,OK)
p1=d.box("파드 ●\nRunning 1/1",345,75,170,70,POD)
p2=d.box("파드 ●\nRunning 1/1",545,75,170,70,POD)
new=d.group("새 ReplicaSet (방금 바꾼 템플릿)",320,200,420,140,BAD)
p3=d.box("파드 ✖\nPending / CrashLoopBackOff …\nReady가 안 됨",345,245,250,80,"fillColor=#B85450;fontColor=#fff;strokeColor=none;fontStyle=1;")
d.box("다음 파드는\n만들지 않고 대기",610,250,115,70,"fillColor=#FFFFFF;strokeColor=#B85450;dashed=1;")
svc=d.box("Service opslab-app\n(대표 전화번호)",820,85,200,60,"fillColor=#E1D5E7;strokeColor=#9673A6;fontStyle=1;")
usr=d.box("사용자 · 부하 파드",1070,85,150,60,GRAY)
d.edge(dep,old,"유지"); d.edge(dep,new,"교체 시도")
d.edge(usr,svc); d.edge(svc,p2,"Ready인 파드에만 전달"); d.edge(svc,p1,"","exitX=0.5;exitY=0;entryX=0.5;entryY=0;",points=[(920,15),(430,15)])
d.box("결과: 서비스는 정상(옛 파드 2개가 받음), 배포만 멈춤\nverify: 희망 2 / 최신 1 / Ready 2 / 전체 3 → '배포 미완료'\n예외: workload-4 ①은 새 파드가 잠깐 Ready가 됐다가 죽어 옛 파드까지 교체됨 → 사용자에게 간헐 오류",780,200,440,140,NOTE+"align=left;spacingLeft=8;")
d.save("docs/diagrams/workload/03-rolling-update.drawio")

# ④ 스케줄러 필터
d=D("4. 스케줄러 — 노드 고르기")
np_=d.box("새 파드\nrequests: cpu 100m, memory 128Mi\nnodeSelector · tolerations",20,150,230,90,POD)
f1=d.box("필터 ① 자리가 있나?\nrequests ≤ Allocatable − 이미 예약된 합\n(실제 사용량이 아니라 '예약 숫자')",300,30,330,80,NOTE)
f2=d.box("필터 ② 지정석 조건이 맞나?\nnodeSelector 라벨이 노드에 있나",300,150,330,80,NOTE)
f3=d.box("필터 ③ 출입 제한을 통과하나?\n노드 taint ↔ 파드 toleration",300,270,330,80,NOTE)
d.edge(np_,f1,"","exitX=0.5;exitY=0;entryX=0;entryY=0.5;",points=[(135,70)])
d.edge(np_,f2)
d.edge(np_,f3,"","exitX=0.5;exitY=1;entryX=0;entryY=0.5;",points=[(135,310)])
nd=d.box("노드 (m6i.large)\nAllocatable CPU ≈ 1930m\n예약됨 ≈ 800m(시스템+앱) → 남음 ≈ 1100m\nTaints: <none>\n라벨: opslab/pool=default …",700,130,300,130,NODE)
for f in (f1,f2,f3): d.edge(f,nd,"통과","strokeColor=#82B366;")
okp=d.box("✔ 배치 → kubelet이 실행",1050,165,170,60,OK+"fontStyle=1;")
d.edge(nd,okp)
pend=d.box("모든 노드가 탈락하면 → Pending\n0/2 nodes are available:\n · 2 Insufficient cpu  ← ①\n · 2 node(s) didn't match Pod's node affinity/selector  ← ②\n · 2 node(s) had untolerated taint {opslab/maintenance: true}  ← ③",300,380,700,120,BAD+"align=left;spacingLeft=10;fontFamily=monospace;fontSize=12;")
d.edge(f3,pend,"어느 필터에서든 모든 노드가 탈락","dashed=1;strokeColor=#B85450;exitX=0.5;exitY=1;entryX=0.24;entryY=0;")
d.save("docs/diagrams/workload/04-scheduler.drawio")

# ⑤ requests·limits·OOM·LimitRange
d=D("5. requests · limits · OOMKilled")
d.text("메모리 (넘으면 강제 종료)",20,20,300,30,"fontStyle=1;fontSize=15;")
scale=3.2  # 1Mi = 3.2px
d.box("",20,60,int(320*scale),50,"fillColor=#FFFFFF;strokeColor=#999999;")
d.box("평소 사용 ≈ 90Mi",20,60,int(90*scale),50,"fillColor=#7EA6E0;strokeColor=none;fontColor=#fff;fontStyle=1;")
for v,lab,col in ((128,"requests 128Mi\n(예약 — 스케줄 기준)","#2F6FB3"),(256,"limits 256Mi\n(상한)","#B85450")):
    d.box("",20+int(v*scale),50,3,70,f"fillColor={col};strokeColor=none;")
    d.text(lab,20+int(v*scale)+6,120,170,40,f"fontColor={col};fontStyle=1;")
d.box("256Mi를 넘는 순간\n→ 커널이 강제 종료\nOOMKilled · Exit Code 137",20+int(256*scale)+20,55,230,60,BAD+"fontStyle=1;")
d.text("CPU (넘으면 느려질 뿐 — 스로틀링)",20,180,400,30,"fontStyle=1;fontSize=15;")
d.box("",20,220,int(320*scale),50,"fillColor=#FFFFFF;strokeColor=#999999;")
d.box("requests 100m",20,220,int(64*scale),50,"fillColor=#7EA6E0;strokeColor=none;fontColor=#fff;fontStyle=1;")
d.box("",20+int(320*scale*0.5),210,3,70,"fillColor=#B85450;strokeColor=none;")
d.text("limits 500m (상한)",20+int(320*scale*0.5)+6,275,200,30,"fontColor=#B85450;fontStyle=1;")
d.box("500m를 넘으려 하면\n→ 속도 제한(스로틀링)\n죽지 않음 · 응답이 느려짐",20+int(256*scale)+20,215,230,60,NOTE+"fontStyle=1;")
lr=d.box("LimitRange app-defaults\n(네임스페이스 기본값 규칙)\ndefault memory 64Mi",20,340,260,80,"fillColor=#E1D5E7;strokeColor=#9673A6;fontStyle=1;")
adm=d.box("파드가 만들어지는 순간(admission)\nresources가 비어 있는 컨테이너에\n기본값을 자동으로 넣음",330,340,300,80,NOTE)
pod=d.box("새 파드: Limits memory 64Mi\n어노테이션 kubernetes.io/limit-ranger:\n'LimitRanger plugin set: …'",680,340,330,80,BAD)
d.edge(lr,adm); d.edge(adm,pod)
d.text("QoS: Guaranteed(requests=limits) > Burstable(오늘 앱) > BestEffort(설정 없음) — 메모리 부족 시 뒤에서부터 쫓겨남 · limits 권장: 평소 사용량의 1.5배 이상",20,440,1100,30,"fontStyle=2;")
d.save("docs/diagrams/workload/05-resources.drawio")

# ⑥ probe 세 가지
d=D("6. probe — 건강검진")
st=d.box("컨테이너 시작",20,150,140,60,GRAY+"fontStyle=1;")
rs=d.box("컨테이너 재시작\n(RESTARTS +1 · 반복되면 CrashLoopBackOff)",200,15,300,70,BAD+"fontStyle=1;")
sp=d.box("startup probe\n'출근 준비 끝났니?'\n(오늘: 2초 × 30회 = 최대 60초)",210,140,230,80,NOTE+"fontStyle=1;")
lv=d.box("liveness probe\n'살아 있니?'\n(오늘: 10초 간격 · timeout 2초 · 3회)",580,10,270,80,NOTE+"fontStyle=1;")
rd_=d.box("readiness probe\n'손님 받을 준비 됐니?'\n(오늘: 5초 간격 · 2회)",580,250,270,80,NOTE+"fontStyle=1;")
okk=d.box("정상 — 계속 반복 검사",920,20,280,60,OK)
ex=d.box("Service 명단(Endpoints)에서 빠짐\n→ 트래픽 안 받음, 재시작은 안 함\n성공하면 다시 명단에 들어감",920,250,280,80,"fillColor=#E1D5E7;strokeColor=#9673A6;")
d.edge(st,sp)
d.edge(sp,rs,"끝내 실패","strokeColor=#B85450;exitX=0.5;exitY=0;entryX=0.5;entryY=1;")
d.edge(sp,lv,"성공하면 검사 시작","exitX=1;exitY=0.3;entryX=0.3;entryY=1;")
d.edge(sp,rd_,"성공하면 검사 시작","exitX=1;exitY=0.8;entryX=0;entryY=0.5;")
d.edge(lv,rs,"연속 실패","strokeColor=#B85450;exitX=0;exitY=0.5;entryX=1;entryY=0.5;")
d.edge(lv,okk,"성공"); d.edge(rd_,ex,"실패")
d.edge(rs,st,"","dashed=1;strokeColor=#B85450;exitX=0;exitY=0.5;entryX=0.5;entryY=0;",points=[(90,50)])
d.text("재시작까지 ≈ (failureThreshold−1 ~ failureThreshold) × periodSeconds  ·  startup 최대 대기 ≈ initialDelay + failureThreshold × periodSeconds  ·  timeout보다 느린 응답 = 실패",20,360,1180,30,"fontStyle=2;")
d.save("docs/diagrams/workload/06-probes.drawio")

# ⑦ 진단 순서
d=D("7. 진단 순서")
s0=d.box("kubectl -n app get pods -o wide\nSTATUS 한 단어 읽기",20,200,230,70,GRAY+"fontStyle=1;")
rows=[("Pending","describe pod → Events: FailedScheduling","describe node: Allocatable · Taints · 라벨"),
      ("ImagePullBackOff","describe pod → Events: Failed to pull image","이미지 주소 · 태그 · 권한(403)"),
      ("Init:0/1","logs <파드> -c wait-db","init의 env · command · image"),
      ("CrashLoopBackOff","describe pod → Last State · Exit Code","logs -c app --previous 마지막 줄"),
      ("OOMKilled (137)","describe pod → Limits · Last State","kubectl top · limitrange · env"),
      ("Running·RESTARTS↑","describe pod → Liveness/Startup 줄 · probe 이벤트","앱 안에서 경로·응답시간 직접 측정")]
y=20
for stt,a,b in rows:
    k=d.box(stt,320,y,190,50,BAD+"fontStyle=1;")
    d.edge(s0,k,"","exitX=1;exitY=0.5;entryX=0;entryY=0.5;",points=[(285,235),(285,y+25)])
    a_=d.box("② "+a,550,y,330,50,NOTE)
    b_=d.box("③④ "+b,920,y,300,50,"fillColor=#FFFFFF;strokeColor=#D6B656;")
    d.edge(k,a_); d.edge(a_,b_)
    y+=75
d.text("⑤ 무엇이 바뀌었나: rollout history · get rs · get deploy -o yaml  |  Headlamp: Pods → 파드 → Events · Logs(Show previous)",20,y+5,1200,30,"fontStyle=1;")
d.save("docs/diagrams/workload/07-diagnosis.drawio")
print("built")
