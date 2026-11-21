# gitops/ — Argo CD 가 읽는 "정답(원하는 상태)"

수강생 Fork 의 그날 브랜치(`opslab/<모듈>-<날짜>`)에서 Argo CD 가 이 폴더를 읽어 클러스터를 이 상태로 맞춘다.

| 경로 | 내용 |
|---|---|
| `apps/` | App of Apps — 앱 목록(목차). 작은 Helm 차트이고, 템플릿 하나가 Argo CD 앱(Application) 하나다 |
| `apps/templates/prod.yaml` | 운영 앱 `opslab-prod` → `app` 네임스페이스 |
| `apps/templates/dev.yaml` | 개발 앱 `opslab-dev` → `app-dev` 네임스페이스 |
| `envs/prod/values.yaml` | 운영 환경 값(샘플 앱 차트 `charts/opslab-app` 기본값에서 바꾸는 것만) |
| `envs/dev/values.yaml` | 개발 환경 값 |
| `root.yaml` | 루트 앱(목차를 읽는 앱) 틀 — Git 에서 읽지 않고 따라하기·K5 층이 학번·계정을 채워 클러스터에 직접 만든다 |

학번·계정 ID 처럼 수강생마다 다른 값은 Git 에 쓰지 않는다. 루트 앱이 `apps/` 차트에 값(valuesObject)으로 넘기고, 자식 앱이 Helm 매개변수로 받는다.
