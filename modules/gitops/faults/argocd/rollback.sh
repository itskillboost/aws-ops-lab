#!/bin/bash
# gitops-6 argocd — rollback. 직접 실행하지 말고 common/inject.sh 로 호출한다.
source "$(dirname "$(readlink -f "$0")")/../../lib.sh"
set +e
kubectl -n argocd scale deploy argocd-repo-server --replicas=1 >/dev/null && echo "  repo-server 1"
kubectl -n argocd scale statefulset argocd-application-controller --replicas=1 >/dev/null && echo "  application-controller 1"
repo_register "$R" && echo "  저장소 등록 토큰을 Secrets Manager 값으로"
kubectl -n argocd rollout status deploy argocd-repo-server --timeout=3m >/dev/null
kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=3m >/dev/null
restore_branch
