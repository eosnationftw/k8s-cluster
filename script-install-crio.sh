#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Load modules
cat <<EOF > /etc/modules-load.d/bridge.conf
bridge
br_netfilter
nf_conntrack_bridge
EOF

# Check modules
cat /etc/modules-load.d/bridge.conf

# Setup iptables for Kubernetes
tee /etc/sysctl.d/99-kubernetes.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Load the bridge module
modprobe bridge
modprobe br_netfilter
modprobe nf_conntrack_bridge

# Check sysctl settings
cat /etc/sysctl.d/99-kubernetes.conf

# Apply sysctl settings
sysctl --system

# Disable swap
swapoff -a

# Update system packages
apt-get update && apt-get upgrade --yes

# Install dependencies
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gpg

apt-get update

#Install CRI-O

export OS="Debian_11"
export VERSION="1.28"

echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

mkdir -p /usr/share/keyrings
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

apt-get update
apt-get install cri-o cri-o-runc

systemctl daemon-reload
systemctl enable --now crio


# Install CNI Plugins
CNI_VERSION="v1.3.0"
mkdir -p /opt/cni/bin
curl -sSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | tar -xz -C /opt/cni/bin

# Add the Kubernetes apt repository
VERSION="1.28"
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Update apt package index, install kubelet, kubeadm and kubectl, and pin their version
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Create cluster configuration file for Kubernetes
cat << EOF > /tmp/cluster-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
    cgroup-driver: systemd
    node-ip: 172.22.1.86
  taints: []
skipPhases:
  - addon/kube-proxy
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  serviceSubnet: "10.96.0.0/16"
  podSubnet: "10.10.0.0/16"
controllerManager:
  extraArgs:
    allocate-node-cidrs: "true"
    node-cidr-mask-size: "20"
#     listen-metrics-urls: http://0.0.0.0:2382
# scheduler:
#   extraArgs:
#     listen-metrics-urls: http://0.0.0.0:2383
# etcd:
#   extraArgs:
#     listen-metrics-urls: http://0.0.0.0:2381
kubernetesVersion: "v1.28.3"
controlPlaneEndpoint: 172.22.1.86
EOF

# Initialize the Kubernetes cluster
kubeadm init --upload-certs --config /tmp/cluster-config.yaml

# Wait for the cluster to initialize
sleep 30

# Setup kubeconfig for the default user
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Install Cilium CNI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
CLI_ARCH=amd64
cd /usr/local/bin
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Install and check Cilium status
cilium install
cilium status --wait
