#!/bin/bash
# 진단(작성자용): gitops-2 ① 순서를 따라 하며 상태를 시간 순으로 찍는다
export LAB=gitops-2
source ~/opslab/modules/gitops/lib.sh; set +e
st() { echo "[$(date +%T)] $1 | spec.selfHeal=$(app_json opslab-prod | jq -c .spec.syncPolicy.automated) | $(app_line opslab-prod) | rev=$(app_json opslab-prod | jq -r '.status.sync.revision[0:7]') | env=$(kubectl -n app get deploy opslab-app -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="APP_ERROR_RATE")].value}') gen=$(kubectl -n app get deploy opslab-app -o jsonpath='{.metadata.generation}')"; }
BASE=$(gh_head "$R" "$B"); st start
commit "$PA" "debug: selfHeal off" 's/selfHeal: true/selfHeal: false/'; kick
for i in $(seq 1 12); do st "after-commit-$i"; sleep 10; done
kubectl -n app set env deploy/opslab-app APP_ERROR_RATE=0.5 >/dev/null; st set-env
for i in $(seq 1 18); do st "after-set-$i"; sleep 10; done
kubectl -n argocd logs statefulset/argocd-application-controller --since=5m | grep opslab-prod | grep -iE 'sync|heal|operation' | tail -15
gh_reset "$R" "$B" "$BASE"; kick; sleep 20; app_sync opslab-prod; sleep 30; st reset
