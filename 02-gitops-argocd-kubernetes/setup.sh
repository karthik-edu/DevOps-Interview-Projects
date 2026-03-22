#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-command bootstrap for Project 02: GitOps with ArgoCD
#
# Usage:
#   export GITHUB_USER="your-github-username"
#   chmod +x setup.sh
#   ./setup.sh
#
# Requirements: Docker running, minikube, kubectl, argocd CLI, gh CLI, git
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-gitops-lab}"
ARGOCD_NS="argocd"
APP_NS="production"
APP_NAME="web-prod"
ARGO_VERSION="v2.11.3"
GITHUB_USER="${GITHUB_USER:-}"
REPO_NAME="${REPO_NAME:-gitops-argocd-demo}"
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGO_PORT="${ARGO_PORT:-8787}"

log()  { echo "[$(date +%T)] $*"; }
ok()   { echo "[$(date +%T)] ✓ $*"; }
fail() { echo "[$(date +%T)] ✗ $*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 1. Prerequisite checks
# --------------------------------------------------------------------------- #
log "Checking prerequisites..."
command -v docker   >/dev/null 2>&1 || fail "docker is not installed"
command -v minikube >/dev/null 2>&1 || fail "minikube is not installed (see README Step 0)"
command -v kubectl  >/dev/null 2>&1 || fail "kubectl is not installed (see README Step 0)"
command -v argocd   >/dev/null 2>&1 || fail "argocd CLI is not installed (see README Step 0)"
command -v git      >/dev/null 2>&1 || fail "git is not installed"
command -v gh       >/dev/null 2>&1 || fail "GitHub CLI (gh) is not installed (see README Step 0)"
docker info >/dev/null 2>&1         || fail "Docker daemon is not running"

if [ -z "${GITHUB_USER}" ]; then
  fail "GITHUB_USER is not set. Run: export GITHUB_USER=your-github-username"
fi

if ! gh auth status >/dev/null 2>&1; then
  fail "GitHub CLI is not authenticated. Run: gh auth login"
fi

ok "Prerequisites satisfied"

# --------------------------------------------------------------------------- #
# 2. Start minikube cluster (idempotent)
# --------------------------------------------------------------------------- #
if minikube status --profile="${MINIKUBE_PROFILE}" 2>/dev/null | grep -q "Running"; then
  ok "minikube profile '${MINIKUBE_PROFILE}' is already running — skipping start"
else
  log "Starting minikube cluster '${MINIKUBE_PROFILE}'..."
  minikube start \
    --profile="${MINIKUBE_PROFILE}" \
    --driver=docker \
    --kubernetes-version=v1.30.0 \
    --cpus=2 \
    --memory=4096
  ok "minikube cluster started"
fi

# Point kubectl at the minikube profile
kubectl config use-context "${MINIKUBE_PROFILE}"

log "Waiting for node to be Ready..."
kubectl wait node --all --for=condition=Ready --timeout=120s
ok "Node is Ready"
kubectl get nodes

# --------------------------------------------------------------------------- #
# 3. Install ArgoCD
# --------------------------------------------------------------------------- #
if kubectl get namespace "${ARGOCD_NS}" >/dev/null 2>&1; then
  ok "ArgoCD namespace already exists — skipping install"
else
  log "Installing ArgoCD ${ARGO_VERSION}..."
  kubectl create namespace "${ARGOCD_NS}"
  kubectl apply -n "${ARGOCD_NS}" \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml"
fi

log "Waiting for argocd-server to roll out (up to 5 min)..."
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NS}" --timeout=300s
ok "ArgoCD is running"

# Patch argocd-server to run without TLS (insecure mode) — required for
# plain gRPC login over kubectl port-forward in a local lab environment.
log "Patching argocd-server to run in insecure (plain HTTP) mode..."
kubectl patch deployment argocd-server \
  -n "${ARGOCD_NS}" \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]' \
  2>/dev/null || true   # no-op if already patched

log "Waiting for argocd-server to re-roll out after patch (up to 3 min)..."
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NS}" --timeout=180s
ok "ArgoCD is running in insecure mode"

# --------------------------------------------------------------------------- #
# 4. Expose ArgoCD and log in
# --------------------------------------------------------------------------- #
log "Port-forwarding ArgoCD server on localhost:${ARGO_PORT}..."
pkill -f "kubectl port-forward.*argocd-server" 2>/dev/null || true
nohup kubectl port-forward svc/argocd-server \
  -n "${ARGOCD_NS}" "${ARGO_PORT}:80" \
  >/tmp/argocd-portforward.log 2>&1 &
PF_PID=$!
disown ${PF_PID}

log "Waiting for port-forward to be ready..."
for i in $(seq 1 20); do
  if curl -s --max-time 2 "http://localhost:${ARGO_PORT}" >/dev/null 2>&1; then
    ok "Port-forward is ready"
    break
  fi
  [ "$i" -eq 20 ] && fail "Port-forward did not become ready after 20 attempts"
  sleep 2
done

ARGO_PWD=$(kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

argocd login "localhost:${ARGO_PORT}" \
  --username admin \
  --password "${ARGO_PWD}" \
  --plaintext
ok "Logged in to ArgoCD (admin password: ${ARGO_PWD})"

# --------------------------------------------------------------------------- #
# 5. Push manifests to GitHub (idempotent)
# --------------------------------------------------------------------------- #
log "Preparing GitOps repository..."

cd "${WORKSPACE_ROOT}"

# Ensure this is a git repo with at least one commit
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  log "Initialising git repo..."
  git init -b main
fi
git add -A
if ! git diff --cached --quiet; then
  git commit -m "Initial GitOps manifests"
fi

REPO_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

if gh repo view "${GITHUB_USER}/${REPO_NAME}" >/dev/null 2>&1; then
  ok "GitHub repo already exists — pushing latest..."
  git remote set-url origin "${REPO_URL}" 2>/dev/null || \
    git remote add origin "${REPO_URL}"
  git push origin main
else
  log "Creating GitHub repo and pushing..."
  # Remove any stale remote before gh creates the repo
  git remote remove origin 2>/dev/null || true
  gh repo create "${GITHUB_USER}/${REPO_NAME}" \
    --public \
    --source . \
    --remote origin \
    --push
fi
ok "Manifests pushed to ${REPO_URL}"

# --------------------------------------------------------------------------- #
# 6. Create ArgoCD Application
# --------------------------------------------------------------------------- #
log "Creating ArgoCD Application '${APP_NAME}'..."
argocd app create "${APP_NAME}" \
  --repo "${REPO_URL}" \
  --path manifests/base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace "${APP_NS}" \
  --sync-policy automated \
  --self-heal \
  --auto-prune \
  --upsert

log "Triggering initial sync..."
argocd app sync "${APP_NAME}"

log "Waiting for application to be Healthy and Synced..."
argocd app wait "${APP_NAME}" \
  --health \
  --sync \
  --timeout 120
ok "Application '${APP_NAME}' is Healthy and Synced"

# --------------------------------------------------------------------------- #
# 7. Verify deployment
# --------------------------------------------------------------------------- #
log "Verifying Kubernetes resources in namespace '${APP_NS}'..."
kubectl get all -n "${APP_NS}"

POD_COUNT=$(kubectl get pods -n "${APP_NS}" \
  -l app=web --field-selector=status.phase=Running \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "${POD_COUNT}" -ge 1 ] || fail "No running pods found in namespace ${APP_NS}"
ok "${POD_COUNT} pod(s) running"

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
echo ""
echo "============================================================"
echo " Project 02 — GitOps with ArgoCD is running"
echo "============================================================"
echo ""
echo "  *** ARGOCD CREDENTIALS ***"
echo "  Username    : admin"
echo "  Password    : ${ARGO_PWD}"
echo ""
echo "  To retrieve the password manually at any time:"
echo "    kubectl -n argocd get secret argocd-initial-admin-secret \\"
echo "      -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "  *** ACCESS & STATUS ***"
echo "  ArgoCD UI   : http://localhost:${ARGO_PORT}"
echo "  App status  : argocd app get ${APP_NAME}"
echo "  Git repo    : ${REPO_URL}"
echo ""
echo "  *** QUICK CHECK STEPS ***"
echo "  1. Open UI   : open https://localhost:${ARGO_PORT}  (or xdg-open on Linux)"
echo "  2. CLI login : argocd login localhost:${ARGO_PORT} --username admin --password '${ARGO_PWD}' --plaintext"
echo "  3. App health: argocd app get ${APP_NAME}"
echo "  4. K8s pods  : kubectl get pods -n ${APP_NS}"
echo ""
echo "  To trigger a GitOps rollout:"
echo "    # edit manifests/base/deployment.yaml (e.g. change image tag)"
echo "    git add . && git commit -m 'upgrade nginx' && git push origin main"
echo "    argocd app wait ${APP_NAME} --health --sync"
echo ""
echo "  To simulate drift:"
echo "    kubectl scale deployment web -n ${APP_NS} --replicas=5"
echo "    sleep 30 && kubectl get deploy web -n ${APP_NS}"
echo "    # ArgoCD self-heals back to 2 replicas"
echo ""
echo "  To clean up everything:"
echo "    minikube delete --profile ${MINIKUBE_PROFILE}"
echo "    gh repo delete ${GITHUB_USER}/${REPO_NAME} --yes"
echo "============================================================"

log "ArgoCD port-forward is running in background (PID ${PF_PID})"
log "Logs: tail -f /tmp/argocd-portforward.log"
log "To stop: kill ${PF_PID}"
