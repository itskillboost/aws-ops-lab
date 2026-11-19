# workload 구축 확인 지점 — common/check.sh 가 source 한다. 단계 이름은 따라하기 페이지의 확인 지점과 같다.
STAGES="cluster metrics data app load"
stage_cluster() {   # 사전 조건: 아침 환경 층(K1) 배포와 Headlamp
  have_cluster && ok "클러스터 $CLUSTER ACTIVE" || { ng "클러스터가 없습니다" "bash ~/opslab/common/start.sh workload"; return; }
  [ "$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)" -ge 2 ] && ok "노드 2대 Ready" || ng "Ready 노드가 2대 미만" "bash ~/opslab/common/start.sh status 로 진행 상황 확인"
  kubectl -n headlamp get deploy headlamp >/dev/null 2>&1 && ok "Headlamp 설치됨" || ng "Headlamp 없음" "bash ~/opslab/common/start.sh workload (이어서 배포)"
  kubectl get storageclass gp3 >/dev/null 2>&1 && ok "StorageClass gp3" || ng "StorageClass gp3 없음" "bash ~/opslab/common/start.sh workload"
}
stage_metrics() {   # 구축 1: metrics-server
  kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1 && ok "metrics-server 설치됨" || { ng "metrics-server 없음" "구축 1 — helm install metrics-server"; return; }
  kubectl top nodes >/dev/null 2>&1 && ok "kubectl top nodes 동작" || ng "kubectl top 이 아직 안 됩니다(설치 뒤 1분 정도 걸림)" "1분 뒤 다시 확인"
}
stage_data() {      # 구축 2: 네임스페이스와 PostgreSQL·Redis
  [ "$(kubectl get ns app -o jsonpath='{.metadata.labels.course}' 2>/dev/null)" = opslab ] && ok "네임스페이스 app (라벨 course=opslab)" || ng "app 네임스페이스나 라벨이 없습니다" "구축 2 — kubectl create namespace / kubectl label"
  [ "$(kubectl -n app get pods -l app.kubernetes.io/name=postgres -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)" = true ] && ok "PostgreSQL Ready" || ng "PostgreSQL 이 Ready 가 아닙니다" "구축 2 — helm install opslab-data"
  [ "$(kubectl -n app get pvc data-postgres-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Bound ] && ok "PostgreSQL 디스크(PVC) Bound" || ng "PVC 가 Bound 가 아닙니다" "막혔을 때 표 — PVC Pending"
  [ "$(kubectl -n app get pods -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)" = true ] && ok "Redis Ready" || ng "Redis 가 Ready 가 아닙니다" "구축 2 — helm install opslab-data"
}
stage_app() {       # 구축 3: 샘플 앱
  local r; r=$(kubectl -n app get deploy opslab-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${r:-0}" -ge 2 ] && ok "opslab-app 파드 ${r}개 Ready" || { ng "opslab-app Ready 파드 ${r:-0}개" "구축 3 — helm install opslab-app"; return; }
  kubectl -n app exec deploy/opslab-app -c app -- python3 -c "import urllib.request as u;print(u.urlopen('http://127.0.0.1:8080/db',timeout=5).read()[:60])" >/dev/null 2>&1 \
    && ok "앱 → DB 조회(/db) 성공" || ng "/db 조회 실패" "구축 3 확인 — kubectl logs deploy/opslab-app"
  kubectl -n app exec deploy/opslab-app -c app -- python3 -c "import urllib.request as u;u.urlopen('http://127.0.0.1:8080/cache',timeout=5)" >/dev/null 2>&1 \
    && ok "앱 → Redis(/cache) 성공" || ng "/cache 실패" "구축 3 확인"
}
stage_load() {      # 2단계(정상 상태 정의): 부하와 기준값
  kubectl -n app get deploy opslab-load >/dev/null 2>&1 && ok "부하 파드 실행 중" || ng "부하 파드 없음" "2단계 — bash ~/opslab/common/load.sh pod"
  [ -f ~/opslab-work/workload/baseline.txt ] && ok "정상 상태 기준값 기록됨" || ng "기준값 기록 없음" "2단계 — bash ~/opslab/modules/workload/baseline/verify.sh"
}
