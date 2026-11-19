#!/bin/bash
# EKS 과정 도구 설치 — CloudShell 홈(~/bin)에 kubectl·helm·eksctl·argocd CLI 를 설치한다. 다시 실행해도 안전하다.
#   bash ~/opslab/common/tools.sh
# CloudShell 홈(~)은 리전마다 1GB 까지 유지되므로 한 번 설치하면 다음 날에도 남아 있다.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
source "$ROOT/common/eks.sh"
B=~/bin; mkdir -p "$B"; cd /tmp
KV=$(cval eks_version); KV=${KV:-1.37}
if ! "$B/kubectl" version --client 2>/dev/null | grep -q "v$KV"; then
  curl -fsSLo "$B/kubectl" "https://dl.k8s.io/release/$(curl -fsSL "https://dl.k8s.io/release/stable-$KV.txt")/bin/linux/amd64/kubectl"
  chmod +x "$B/kubectl"
fi
if ! command -v "$B/helm" >/dev/null; then
  curl -fsSL https://get.helm.sh/helm-v3.16.3-linux-amd64.tar.gz | tar xz -C "$B" --strip-components 1 linux-amd64/helm
fi
if ! command -v "$B/eksctl" >/dev/null; then
  curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C "$B"
fi
if ! command -v "$B/argocd" >/dev/null; then
  curl -fsSLo "$B/argocd" https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && chmod +x "$B/argocd"
fi
python3 -c 'import yaml' 2>/dev/null || pip3 install --user --quiet pyyaml
grep -q 'HOME/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
grep -q 'kubectl completion' ~/.bashrc 2>/dev/null || echo 'source <(kubectl completion bash); alias k=kubectl; complete -o default -F __start_kubectl k' >> ~/.bashrc
echo "✅ 도구 설치 완료"
"$B/kubectl" version --client | head -1; "$B/helm" version --short; "$B/eksctl" version; "$B/argocd" version --client --short 2>/dev/null | head -1
echo "새 터미널에서는 자동으로 적용됩니다. 지금 터미널에서는: source ~/.bashrc"
