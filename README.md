# aws-ops-lab — Ops Lab (AWS 인프라 운영 장애 대응 실습)

수강생이 자기 AWS 계정에서 장애를 직접 주입·관찰·복구하며 운영 절차를 익히는 실습 모듈 모음입니다.
모듈은 과정·고객사·Day 번호와 무관하게 만들고, 과정마다 `courses/<과정ID>.yaml` 하나로 조립합니다.

| 경로 | 내용 |
|---|---|
| `courses/<과정ID>.yaml` | 과정 파일: 고객사·계정 제공사·Notion·도메인, Day↔모듈 순서 |
| `modules/<모듈ID>/module.yaml` | 모듈 정의: 제목, 필요한 환경 층(requires), 직접 구축하는 층(builds), Lab 목록 |
| `modules/<모듈ID>/faults/<장애명>/{inject,verify,rollback}.sh` | 장애별 3종 세트 |
| `modules/<모듈ID>/baseline/verify.sh` | 정상 상태 정의(2단계) 판정 |
| `modules/<모듈ID>/{lib,cleanup}.sh` | 모듈 공통 함수, 매일 정리 훅(CLI로 직접 만든 리소스 삭제) |
| `modules/<모듈ID>/{env,done}.yaml` | (선택) 모듈 주변 구성 템플릿, 직접 구축하는 것의 완료 상태 템플릿(따라잡기·시험용) |
| `layers/l0-guard.yaml` | L0 보호 장치(Day 0에 1회): 강사 읽기 전용 역할, FIS 역할, Budgets, 하위 도메인, 권한 경계 |
| `layers/l1-network.yaml`, `l2-app.yaml`, `l3-data.yaml`, `l4-secret.yaml` … | 환경 층 L1(네트워크 기반)·L2(앱 계층 = cmp 완료 상태)·L3(데이터 계층 = data 완료 상태)·L4(시크릿 계층 = sec 완료 상태) … `<층>.init.sh` 가 있으면 배포 뒤 실행 |
| `common/start.sh <모듈ID> [full]` | 모듈에 필요한 환경 층 배포(full: 직접 구축할 층까지 = 따라잡기) |
| `common/inject.sh <Lab ID>` | 장애 주입·해결 기록(done)·원복(rollback)·현황(status) |
| `common/{load,cleanup}.sh` | 부하 도구, 매일 정리(L0 층을 뺀 전부 삭제) |
| `tools/test-module.sh <모듈ID>` | 모듈 독립 시험(층 배포 → verify → 모든 변형 주입·원복 → 정리). `DEEP=<초>` 주입 후 증상·원복 후 판정까지 검사 |
| `tools/build/<모듈ID>.sh` | 따라하기 1단계 명령 모음(작성자 검증용) |
| `app/` | Flask 샘플 앱 (/health · /api · /db · /slow) |
| `runbook/TEMPLATE.md` | 런북 양식 |

| 모듈 ID | 모듈 | requires | builds |
|---|---|---|---|
| cmp | 컴퓨팅과 로드밸런싱 장애 | L1 | L2 |
| net | 네트워크 연결 장애 (주변 구성 env.yaml, 완료 상태 done.yaml, 경로 점검 probe.sh) | L2 | — |
| data | 데이터 계층 운영 (Aurora PostgreSQL, 점검 probe.sh, L3 초기화 layers/l3-data.init.sh) | L2 | L3 |
| sec | 시크릿과 인증 운영 (KMS·Secrets Manager·Vault — 동적 자격증명·PKI·Transit, 점검 probe.sh, L4 초기화 layers/l4-secret.init.sh) | L3 | L4 |
| iac | IaC 운영과 드리프트 (수강생 스택 modules/iac/iac-app.yaml, 따라잡기 full.sh) | L2 | — |
| sec · iac · cicd · auto · rel | (작성 예정) | | |

이름: `<학번>-<모듈ID|base>-<역할>` · 태그: `Course=opslab`, `Module=<모듈ID|base>`, `Owner=<학번>` · Lab ID: `<모듈ID>-<번호>` · 주입 기록: SSM `/opslab/injections/<Lab ID>`

## EKS 과정(2단계) — 과정 파일 `courses/skons-eks.yaml`

| 경로 | 내용 |
|---|---|
| `common/tools.sh` | CloudShell 홈(~/bin)에 kubectl·helm·eksctl·argocd 설치 |
| `common/eks.sh` | EKS 공통 함수(과정 값 cval, 미러 이미지 주소 img, kubeconfig) |
| `common/start.sh <모듈ID> [full] \| status` | L1 → K1… 층을 이어서 배포(끝난 층은 건너뜀), 작업 폴더·가설·런북 양식 생성 |
| `common/inject.sh retry <Lab ID>` | 원복한 Lab 에 같은 변형 재주입(재도전). `done` 은 인지·원인 확정 시각을 묻는다 |
| `common/check.sh <모듈ID> <단계>\|all\|day0\|final` | 구축 확인 지점 ✅/❌ |
| `common/review.sh <Lab ID>\|<모듈ID>\|final` | 실습 검토(review.yaml), 포트폴리오 |
| `common/headlamp.sh` | Headlamp 접속 허용 IP 등록 + 8시간 로그인 토큰 |
| `common/load.sh pod [log\|stop]` | ALB 가 없는 날의 클러스터 내 부하 파드 |
| `layers/k1-cluster.yaml` + `.init.sh` | K1: EKS·노드 그룹·OIDC·애드온·Container Insights·접근 항목 + StorageClass·Headlamp |
| `layers/k2-workload.sh` | K2: metrics-server(관리형 애드온)·PostgreSQL·Redis·샘플 앱 |
| `charts/opslab-app`, `charts/opslab-data`, `vendor/charts/` | 앱·데이터 차트, 버전 고정 외부 차트 |
| `app/Dockerfile` | 샘플 앱 컨테이너(강사가 `tools/mirror-images.sh` 로 ECR Public 에 올림) |
| `modules/workload/` | 워크로드 장애(workload-1~6, faults/*/review.yaml 포함) |
