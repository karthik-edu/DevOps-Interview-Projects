#!/usr/bin/env bash
# =============================================================================
# scripts/controlplane.sh — Run on the control-plane node ONLY
#
# Injected variables (prepended by setup.sh):
#   CP_IP           External IP of this VM
#   K8S_VERSION     e.g. "1.30"
#   CALICO_VERSION  e.g. "v3.28.0"
# =============================================================================

set -euo pipefail

echo "[controlplane] === Starting control-plane initialisation ==="

# --------------------------------------------------------------------------- #
# Idempotency: skip kubeadm init if cluster is already bootstrapped
# --------------------------------------------------------------------------- #
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "[controlplane] Cluster already initialised — skipping kubeadm init"
else

  # ----------------------------------------------------------------------- #
  # 1. kubeadm init
  #
  # Detect the exact version installed by apt (e.g. v1.30.5) so the
  # kubeadm-config kubernetesVersion field matches the binary exactly.
  # Hardcoding "v1.30.0" causes kubeadm to error if apt installed v1.30.5.
  # ----------------------------------------------------------------------- #
  ACTUAL_K8S_VER=$(kubeadm version -o short 2>/dev/null | tr -d 'v' || echo "${K8S_VERSION}.0")

  cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v${ACTUAL_K8S_VER}"
networking:
  podSubnet: "192.168.0.0/16"
apiServer:
  advertiseAddress: "${CP_IP}"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

  echo "[controlplane] Running kubeadm init (kubernetesVersion=v${ACTUAL_K8S_VER})..."
  kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs 2>&1 \
    | tee /tmp/kubeadm-init.log

  echo "[controlplane] kubeadm init complete"

fi

# --------------------------------------------------------------------------- #
# 2. Configure kubectl for root and ubuntu users
# --------------------------------------------------------------------------- #
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

if id ubuntu >/dev/null 2>&1; then
  mkdir -p /home/ubuntu/.kube
  cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
  chown ubuntu:ubuntu /home/ubuntu/.kube/config
fi

export KUBECONFIG=/etc/kubernetes/admin.conf
echo "[controlplane] kubectl configured"

# --------------------------------------------------------------------------- #
# 3. Install Calico CNI
#    podSubnet 192.168.0.0/16 must match Calico's default CALICO_IPV4POOL_CIDR
# --------------------------------------------------------------------------- #
# Check if Calico is already deployed before applying
if kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
  echo "[controlplane] Calico already installed — skipping"
else
  echo "[controlplane] Installing Calico ${CALICO_VERSION}..."
  kubectl apply -f \
    "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
  echo "[controlplane] Calico manifest applied"
fi

# Wait for the Calico DaemonSet to finish rolling out.
# Add a brief sleep first — the DaemonSet object may not be registered yet
# if we checked immediately after `kubectl apply`.
echo "[controlplane] Waiting for Calico DaemonSet to roll out (up to 3 min)..."
sleep 10
kubectl rollout status daemonset/calico-node -n kube-system --timeout=180s
echo "[controlplane] Calico is running"

# --------------------------------------------------------------------------- #
# 4. Wait for control-plane node to be Ready
# --------------------------------------------------------------------------- #
echo "[controlplane] Waiting for control-plane node to be Ready..."
for i in $(seq 1 24); do
  STATUS=$(kubectl get node "$(hostname)" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
  if [ "${STATUS}" = "True" ]; then
    echo "[controlplane] Node is Ready"
    break
  fi
  [ "${i}" -eq 24 ] && echo "[controlplane] WARNING: node not Ready after 4 min — check CNI logs" && break
  echo "  ... waiting (${i}/24, Ready=${STATUS})"
  sleep 10
done

kubectl get nodes
echo "[controlplane] === Control-plane initialisation complete ==="
