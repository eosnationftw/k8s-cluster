#!/bin/bash
# Note: This script must be run as root
# Make sure those steps are done before running this script:
# Download the Google Cloud public signing key
#curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
# Add the Kubernetes apt repository
#echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Stop script on error
set -e

# Disable swap
swapoff -a

# Verify the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Exécutez le script en tant que root ou avec sudo"
  exit
fi

# Install packages
apt update
apt install -y git conntrack socat ipset curl wget gnupg

# Install containerd
curl -LJO https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz
curl -LJO https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz.sha256sum

# Verify containerd and unzip files
tar_file="containerd-1.7.2-linux-amd64.tar.gz"
tar Cxzvf /usr/local $tar_file

# Activate containerd as a systemd service
curl -LJO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mkdir -p /usr/local/lib/systemd/system
mv containerd.service /usr/local/lib/systemd/system

systemctl daemon-reload
systemctl enable --now containerd

# Create config file containerd
mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | tee /etc/containerd/config.toml > /dev/null

# Install runc
curl -LJO https://github.com/opencontainers/runc/releases/download/v1.1.8/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# Install plugins CNI
curl -LJO https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz

# Activate and verify IP forwarding
sysctl net.ipv4.ip_forward=1

# Activate and verify bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-iptables=1

# (Omettant la section sur les modules du noyau pour la brièveté)

# Install cilium-cli
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin

apt-get update
apt-get install -y apt-transport-https ca-certificates kubelet kubeadm kubectl

cat << EOF | tee ./kubeadm-config.yaml > /dev/null
---
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: v1.28.1
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
EOF

kubeadm init --config ./kubeadm-config.yaml
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Let the cluster get created
sleep 5

kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Install Cilium CNI
cilium install --version 1.14.1
cilium status --wait

# Cleanup
rm -rf cilium-linux-amd64.tar.gz
rm -rf cilium-linux-amd64.tar.gz.sha256sum
rm -rf cni-plugins-linux-amd64-v1.3.0.tgz
rm -rf containerd-1.7.2-linux-amd64.tar.gz
rm -rf containerd-1.7.2-linux-amd64.tar.gz.sha256sum
rm -rf kubeadm-config.yaml
rm -rf runc.amd64
rm -rf kubeadm-config.yaml