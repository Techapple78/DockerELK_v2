#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${1:-}"

if [[ ! "${ARGOCD_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vX.Y.Z" >&2
  exit 2
fi

kubectl get nodes
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply \
  --server-side \
  --force-conflicts \
  --namespace argocd \
  --filename "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl wait \
  --namespace argocd \
  --for=condition=Available \
  --timeout=600s \
  deployment/argocd-server

echo "Argo CD ${ARGOCD_VERSION} est disponible."
echo "Acces local : kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Mot de passe initial :"
kubectl \
  --namespace argocd \
  get secret argocd-initial-admin-secret \
  --output jsonpath='{.data.password}' | base64 --decode
echo
