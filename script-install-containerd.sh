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
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

# Set up the stable repository for containerd
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Update the apt package index with the new repository
apt-get update

# Install containerd
curl -LJO https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz
curl -LJO https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz.sha256sum
tar_file="containerd-1.7.2-linux-amd64.tar.gz"
sudo tar Cxzvf /usr/local $tar_file
curl -LJO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo mkdir -p /usr/local/lib/systemd/system
sudo mv containerd.service /usr/local/lib/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable --now containerd


sudo mkdir -p /etc/containerd

containerd config default \
    | sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
    | sudo tee /etc/containerd/config.toml > /dev/null

sudo install -m 755 runc.amd64 /usr/local/sbin/runc

systemctl restart containerd

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
