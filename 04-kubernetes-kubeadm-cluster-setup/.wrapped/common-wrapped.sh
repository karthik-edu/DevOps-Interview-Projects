K8S_VERSION=1.30
#!/usr/bin/env bash
# =============================================================================
# scripts/common.sh — Run on EVERY node (control-plane and workers)
#
# Injected variable (prepended by setup.sh):
#   K8S_VERSION  e.g. "1.30"
# =============================================================================

set -euo pipefail

echo "[common] === Starting node preparation ==="

# Idempotency: if kubeadm is already installed and the right K8S_VERSION
# packages are present, skip the heavy package installation steps.
if command -v kubeadm >/dev/null 2>&1; then
  echo "[common] kubeadm already installed — skipping package installation"
else

  # ----------------------------------------------------------------------- #
  # 1. Disable swap (kubelet refuses to start with swap enabled)
  # ----------------------------------------------------------------------- #
  swapoff -a
  # Persist across reboots: comment out swap entries in /etc/fstab
  sed -i '/\bswap\b/s/^/#/' /etc/fstab
  echo "[common] Swap disabled"

  # ----------------------------------------------------------------------- #
  # 2. Kernel modules
  #    overlay   — required by containerd for the OverlayFS storage driver
  #    br_netfilter — required so iptables sees bridged traffic (kube-proxy)
  # ----------------------------------------------------------------------- #
  cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
  modprobe overlay
  modprobe br_netfilter
  echo "[common] Kernel modules loaded (overlay, br_netfilter)"

  # ----------------------------------------------------------------------- #
  # 3. Sysctl — IP forwarding + bridge traffic to iptables
  # ----------------------------------------------------------------------- #
  cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sysctl --system >/dev/null
  echo "[common] sysctl parameters applied"

  # ----------------------------------------------------------------------- #
  # 4. containerd
  #    SystemdCgroup = true is mandatory: kubelet and containerd must agree
  #    on the cgroup driver. On Ubuntu 22.04 systemd owns cgroups.
  # ----------------------------------------------------------------------- #
  apt-get update -qq
  apt-get install -y -qq containerd apt-transport-https ca-certificates curl gpg

  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  systemctl enable --now containerd
  systemctl restart containerd
  echo "[common] containerd installed (SystemdCgroup=true)"

  # ----------------------------------------------------------------------- #
  # 5. Kubernetes apt repository + kubeadm / kubelet / kubectl
  # ----------------------------------------------------------------------- #
  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list

  apt-get update -qq
  apt-get install -y -qq kubelet kubeadm kubectl

  # Hold versions — prevents accidental upgrade breaking the cluster
  apt-mark hold kubelet kubeadm kubectl

  systemctl enable kubelet
  echo "[common] kubeadm / kubelet / kubectl installed (K8s ${K8S_VERSION})"

fi  # end idempotency guard

echo "[common] === Node preparation complete ==="
