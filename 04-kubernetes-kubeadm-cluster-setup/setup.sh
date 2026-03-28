#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-command bootstrap for Project 04: kubeadm Kubernetes Cluster
#
# Usage:
#   chmod +x setup.sh && ./setup.sh
#
# What it does:
#   1. Installs multipass if missing (requires snap)
#   2. Provisions 3 Ubuntu 22.04 VMs: 1 control-plane + 2 workers
#   3. Installs containerd + kubeadm on every node
#   4. Runs kubeadm init on the control-plane, installs Calico CNI
#   5. Joins both worker nodes to the cluster
#   6. Deploys a test nginx workload and verifies it
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
K8S_VERSION="1.30"
CALICO_VERSION="v3.28.0"
CP_VM="k8s-control"
WORKER_VMS=("k8s-worker-1" "k8s-worker-2")
VM_CPUS="2"
VM_MEM="2G"
VM_DISK="10G"
VM_IMAGE="22.04"
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_LOCAL="${WORKSPACE_ROOT}/kubeconfig"

log()  { echo "[$(date +%T)] $*"; }
ok()   { echo "[$(date +%T)] ✓ $*"; }
fail() { echo "[$(date +%T)] ✗ $*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 1. Prerequisites
# --------------------------------------------------------------------------- #
log "Checking prerequisites..."

if ! command -v multipass >/dev/null 2>&1; then
  log "multipass not found — installing via snap..."
  command -v snap >/dev/null 2>&1 || fail "snap is not available; install multipass manually"
  sudo snap install multipass
  ok "multipass installed"
  # Wait for the multipassd daemon to fully initialize (generates root cert, etc.)
  log "Waiting for multipassd to be ready..."
  for i in $(seq 1 30); do
    if multipass version >/dev/null 2>&1; then
      break
    fi
    [ "${i}" -eq 30 ] && fail "multipassd did not become ready after 30 s"
    sleep 1
  done
fi

command -v kubectl >/dev/null 2>&1 || \
  fail "kubectl not installed — run: snap install kubectl --classic"

MULTIPASS_VER=$(multipass version | head -1)
ok "Prerequisites satisfied — ${MULTIPASS_VER}"

# --------------------------------------------------------------------------- #
# 2. Provision VMs (idempotent)
# --------------------------------------------------------------------------- #
provision_vm() {
  local name=$1
  if multipass info "${name}" >/dev/null 2>&1; then
    ok "VM '${name}' already exists — skipping"
  else
    log "Creating VM '${name}'..."
    multipass launch "${VM_IMAGE}" \
      --name "${name}" \
      --cpus "${VM_CPUS}" \
      --memory "${VM_MEM}" \
      --disk "${VM_DISK}"
    ok "VM '${name}' created"
  fi
}

provision_vm "${CP_VM}"
for w in "${WORKER_VMS[@]}"; do provision_vm "${w}"; done

# --------------------------------------------------------------------------- #
# Helper: inject variables + transfer + run as root on a VM
#
# We prepend exported variables to a temp file (no extra shebang — the inner
# script already has one and bash ignores shebangs beyond line 1).
# Critical: use `sudo bash` — multipass exec runs as the ubuntu user which
# has no permission to run apt-get, modprobe, kubeadm, etc.
# --------------------------------------------------------------------------- #
run_script_on() {
  local vm=$1 script=$2
  local remote="/tmp/$(basename "${script}")"
  multipass transfer "${script}" "${vm}:${remote}"
  multipass exec "${vm}" -- sudo bash "${remote}"
}

# Build a self-contained wrapper that prepends variables before the script body
make_wrapper() {
  local dest=$1; shift          # output path
  local vars_block=""
  while [ $# -ge 2 ]; do
    vars_block+="$(printf '%s=%q\n' "$1" "$2")"   # safe quoting for all values
    shift 2
  done
  # Do NOT add a second shebang — the inner script already has one
  printf '%s\n' "${vars_block}" | cat - "${!#}" > "${dest}" 2>/dev/null || true
  # Fallback: direct concat
  { printf '%s\n' "${vars_block}"; cat "${dest##*,}"; } 2>/dev/null || true
}

# Simpler, explicit wrapper builder used below
inject_and_wrap() {
  local outfile=$1 script=$2
  shift 2
  # $@ = pairs of VAR VALUE
  (
    while [ $# -ge 2 ]; do
      printf '%s=%q\n' "$1" "$2"
      shift 2
    done
    cat "${script}"
  ) > "${outfile}"
}

# --------------------------------------------------------------------------- #
# 3. Install containerd + kubeadm on every node (idempotent inside the script)
# --------------------------------------------------------------------------- #
mkdir -p "${WORKSPACE_ROOT}/.wrapped"
log "Installing container runtime and Kubernetes components on all nodes..."

WRAPPED_COMMON="${WORKSPACE_ROOT}/.wrapped/common-wrapped.sh"
inject_and_wrap "${WRAPPED_COMMON}" \
  "${WORKSPACE_ROOT}/scripts/common.sh" \
  K8S_VERSION "${K8S_VERSION}"

run_script_on "${CP_VM}" "${WRAPPED_COMMON}"
for w in "${WORKER_VMS[@]}"; do
  run_script_on "${w}" "${WRAPPED_COMMON}"
done
ok "All nodes: containerd + kubelet + kubeadm installed"

# --------------------------------------------------------------------------- #
# 4. Initialise the control-plane
# --------------------------------------------------------------------------- #
log "Initialising Kubernetes control-plane on '${CP_VM}'..."

CP_IP=$(multipass info "${CP_VM}" | awk '/IPv4/ { print $2; exit }')
[ -n "${CP_IP}" ] || fail "Could not determine IP of ${CP_VM}"
ok "Control-plane IP: ${CP_IP}"

WRAPPED_CP="${WORKSPACE_ROOT}/.wrapped/controlplane-wrapped.sh"
inject_and_wrap "${WRAPPED_CP}" \
  "${WORKSPACE_ROOT}/scripts/controlplane.sh" \
  CP_IP         "${CP_IP}" \
  K8S_VERSION   "${K8S_VERSION}" \
  CALICO_VERSION "${CALICO_VERSION}"

run_script_on "${CP_VM}" "${WRAPPED_CP}"
ok "Control-plane initialised and Calico installed"

# --------------------------------------------------------------------------- #
# 5. Retrieve kubeconfig and join command
# --------------------------------------------------------------------------- #
log "Fetching kubeconfig from control-plane..."
multipass exec "${CP_VM}" -- sudo cat /etc/kubernetes/admin.conf > "${KUBECONFIG_LOCAL}"

# Rewrite the server address from the internal loopback to the VM's external IP
# Use an explicit field match to avoid greedy over-replacement
sed -i "s|server: https://[^/]*:6443|server: https://${CP_IP}:6443|g" \
  "${KUBECONFIG_LOCAL}"
chmod 600 "${KUBECONFIG_LOCAL}"
ok "kubeconfig saved → ${KUBECONFIG_LOCAL}"

# Merge into ~/.kube/config so all terminals pick it up automatically (idempotent)
log "Merging kubeconfig into ~/.kube/config..."
mkdir -p "${HOME}/.kube"
if [ -f "${HOME}/.kube/config" ]; then
  KUBECONFIG="${HOME}/.kube/config:${KUBECONFIG_LOCAL}" kubectl config view --flatten > /tmp/kube-merged.conf
  mv /tmp/kube-merged.conf "${HOME}/.kube/config"
else
  cp "${KUBECONFIG_LOCAL}" "${HOME}/.kube/config"
fi
chmod 600 "${HOME}/.kube/config"
ok "kubeconfig merged → ~/.kube/config (all terminals ready)"

log "Generating worker join command..."
# Do NOT suppress stderr — if this fails we need to see why
JOIN_CMD=$(multipass exec "${CP_VM}" -- sudo kubeadm token create --print-join-command)
[ -n "${JOIN_CMD}" ] || fail "kubeadm token create returned an empty join command"

# --------------------------------------------------------------------------- #
# 6. Join worker nodes
# --------------------------------------------------------------------------- #
for w in "${WORKER_VMS[@]}"; do
  log "Joining '${w}' to the cluster..."
  WRAPPED_W="${WORKSPACE_ROOT}/.wrapped/worker-wrapped-${w}.sh"
  inject_and_wrap "${WRAPPED_W}" \
    "${WORKSPACE_ROOT}/scripts/worker.sh" \
    JOIN_CMD "${JOIN_CMD}"
  run_script_on "${w}" "${WRAPPED_W}"
  ok "'${w}' joined"
done

# --------------------------------------------------------------------------- #
# 7. Wait for all nodes to be Ready
# --------------------------------------------------------------------------- #
log "Waiting for all nodes to be Ready (up to 3 min)..."
export KUBECONFIG="${KUBECONFIG_LOCAL}"

for i in $(seq 1 18); do
  # Use `|| true` inside the subshell so grep's exit-1-on-no-match
  # doesn't propagate through set -e and kill the script when nodes ARE ready
  NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null \
    | { grep -v " Ready" || true; } | wc -l)
  TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

  if [ "${NOT_READY}" -eq 0 ] && [ "${TOTAL}" -ge 3 ]; then
    ok "All ${TOTAL} nodes are Ready"
    break
  fi
  [ "${i}" -eq 18 ] && fail "Nodes not Ready after 3 min — run: kubectl get nodes"
  echo "  ... waiting (${i}/18, total=${TOTAL}, not-ready=${NOT_READY})"
  sleep 10
done

kubectl get nodes -o wide

# --------------------------------------------------------------------------- #
# 8. Deploy test workload
# --------------------------------------------------------------------------- #
log "Deploying test nginx workload..."
kubectl apply -f "${WORKSPACE_ROOT}/manifests/test-deployment.yaml"

log "Waiting for nginx-demo deployment to roll out (up to 2 min)..."
kubectl rollout status deployment/nginx-demo --timeout=300s
ok "Test deployment is running"

kubectl get pods -l app=nginx-demo -o wide

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
echo ""
echo "============================================================"
echo " Project 04 — Kubernetes Cluster (kubeadm) is running"
echo "============================================================"
echo "  Control-plane : ${CP_VM} (${CP_IP})"
for w in "${WORKER_VMS[@]}"; do
  W_IP=$(multipass info "${w}" | awk '/IPv4/ { print $2; exit }')
  echo "  Worker        : ${w} (${W_IP})"
done
echo ""
echo "  Use the cluster:"
echo "    export KUBECONFIG=${KUBECONFIG_LOCAL}"
echo "    kubectl get nodes -o wide"
echo "    kubectl get pods -A"
echo ""
echo "  To simulate node failure:"
echo "    multipass stop k8s-worker-1"
echo "    kubectl get nodes          # worker-1 → NotReady after ~40 s"
echo "    kubectl get pods -o wide   # pods reschedule to worker-2"
echo "    multipass start k8s-worker-1"
echo ""
echo "  To clean up:"
echo "    multipass delete ${CP_VM} ${WORKER_VMS[*]} && multipass purge"
echo "    rm -f ${KUBECONFIG_LOCAL}"
echo "============================================================"
