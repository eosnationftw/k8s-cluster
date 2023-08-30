# K8s-firehose

This guide will show you everything that you
need to get started with kubernetes on bare-metal
cluster.

This repo will deploy the fireeth stack using flux and kubeadm.

## Prerequisites

1. System requirements

   Each node should have the following:

   - 2GB RAM
   - 2 CPUs
   - **NO SWAP** (Otherwise `kubelet` will fail)
   - 8GB Disk

   \
    Note that this demo will set up a cluster using a single node as a controller/worker.
   More work will be done in the future to make a HA deployment.

2. Install needed packages on the node

   ```bash
   sudo apt install git conntrack socat ipset curl wget gnupg -y
   ```

3. Installing containerd

   **Make sure to read this!**

   **The steps below will show how to install the required runtime dependencies for**
   **kubernetes to run. An alternative and albeit simpler way to do this would**
   **probably be to install `containerd.io` through `docker` since the project**
   **itself doesn't distribute the software.**

   **However, this is distro specific and may not work on your machine. Also, keep**
   **in mind that docker does not install the `CNI plugins` so you will still need**
   **to install these manually.**

   **In my opinion, the simplest way to install these dependencies is through**
   **their github release page since it should work on any distro.**

   In this demo, we will be using containerd, runc and the CNI plugins.

   ```bash
   curl -LJO https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz
   curl -LJO https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-amd64.tar.gz.sha256sum
   ```

   After downloading the files, verify the checksum and extract into `/usr/local`

   ```bash
   tar_file="containerd-1.7.2-linux-amd64.tar.gz"
   sudo tar Cxzvf /usr/local $tar_file
   ```

   You can now enable `containerd` as a `systemd` service

   ```bash
   curl -LJO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
   sudo mkdir -p /usr/local/lib/systemd/system
   sudo mv containerd.service /usr/local/lib/systemd/system

   sudo systemctl daemon-reload
   sudo systemctl enable --now containerd
   ```

   Finally, you will need to create a `containerd` config file
   located in `/etc/containerd/config.toml`.

   ```bash
   sudo mkdir -p /etc/containerd

   containerd config default \
       | sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
       | sudo tee /etc/containerd/config.toml > /dev/null
   ```

   This configuration assumes you are using `systemd` as the init system and thus
   we should specify that `systemd` will be the cgroup manager.

4. Installing runc

   Then you can install the `runc` container runtime

   ```bash
   curl -LJO https://github.com/opencontainers/runc/releases/download/v1.1.8/runc.amd64
   sudo install -m 755 runc.amd64 /usr/local/sbin/runc
   ```

5. Installing the CNI plugins

   To install the CNI plugins, use the following command:

   ```bash
   curl -LJO https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
   sudo mkdir -p /opt/cni/bin
   sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
   ```

6. Enabling IP forwarding

   Run the following command to check the current value of `/proc/sys/net/ipv4/ip_forward`:

   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   ```

   If the output is `0`, IP forwarding is disabled. To enable it, execute the following
   command:

   ```bash
   sudo sysctl net.ipv4.ip_forward=1
   ```

7. Enable bridge-nf-call-iptables

   Run the following command to check the current value of `/proc/sys/net/bridge/bridge-nf-call-iptables`:

   ```bash
   cat /proc/sys/net/bridge/bridge-nf-call-iptables
   ```

   If the output is not `1`, you need to set it to `1` to enable `bridge-nf-call-iptables`.
   Use the following command:

   ```bash
   sudo sysctl net.bridge.bridge-nf-call-iptables=1
   ```

   If the file `/proc/sys/net/bridge/bridge-nf-call-iptables` does not exist on
   your system, it likely means that your kernel does not support the necessary
   bridge netfilter modules or that they are not enabled.

   To resolve this issue, you'll need to enable the required kernel modules.
   Here's how you can do that:

   1. Check if the bridge module is loaded:

      Run the following command to see if the `bridge` module is loaded:

      ```bash
      lsmod | grep bridge
      ```

      If you see output similar to `bridge`, the module is already loaded. If not, you'll need to load it. You can load it using the `modprobe` command:

      ```bash
      sudo modprobe bridge
      ```

   2. Enable bridge netfilter modules:
      Some Linux distributions require explicit loading of the bridge netfilter
      modules. Use the following commands to load them:

      ```bash
      sudo modprobe br_netfilter
      sudo modprobe nf_conntrack_bridge
      ```

   3. Persist the changes:

      If the above steps resolved the issue, you'll need to persist these changes
      so that the modules are loaded on every system reboot. Create a new file
      called `bridge.conf` in the `/etc/modules-load.d/` directory (if it doesn't
      exist already) and add the following lines to it:

      ```text
      bridge
      br_netfilter
      nf_conntrack_bridge
      ```

8. Installing cilium-cli

   To be able to network pods together, we will need a Container Network Interface.
   In this setup, we use Cilium.

   ```bash
   CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
   CLI_ARCH=amd64
   if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
   curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
   sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
   sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
   rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
   ```

After performing these steps, you should be able to proceed with your Kubernetes
installation without encountering any error.

## Installing the Cluster with Kubeadm

1. Install the kubernetes tools

   ```bash
   # Update the apt package index and install packages needed to use the Kubernetes apt repository
   sudo apt-get update
   sudo apt-get install -y apt-transport-https ca-certificates

   # Download the Google Cloud public signing key
   curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

   # Add the Kubernetes apt repository
   echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

   # Update apt package index, install kubelet, kubeadm and kubectl, and pin their version
   sudo apt-get update
   sudo apt-get install -y kubelet kubeadm kubectl
   sudo apt-mark hold kubelet kubeadm kubectl
   ```

2. Create the kubelet configuration file

   ```bash
   cat << EOF | tee ./kubeadm-config.yaml > /dev/null
   ---
   kind: ClusterConfiguration
   apiVersion: kubeadm.k8s.io/v1beta3
   kubernetesVersion: v1.27.1
   ---
   kind: KubeletConfiguration
   apiVersion: kubelet.config.k8s.io/v1beta1
   cgroupDriver: systemd
   EOF
   ```

3. Install kubernetes with kubeadm

   ```bash
   sudo kubeadm init --config ./kubeadm-config.yaml
   ```

   After running this command, kubeadm will output some more commands to do. It
   should give you the location of the `KUBECONFIG` file in `/etc/kubernetes/admin.conf`
   as well as a token to use to join worker nodes to the cluster.

   Follow these instructions on each node and when completed proceed to the
   installing of Cilium on the control node.

4. Installing the Cilium CNI

   ```bash
   cilium install --version 1.14.1
   ```

   To validate that Cilium has been properly installed, you can run

   ```bash
   cilium status --wait
   ```

   Run the following command to validate that your cluster has proper network connectivity:

   ```bash
   cilium connectivity test
   ```

## Deploying the Firehose App Using FluxCD

By default, your cluster will not schedule Pods on the control plane nodes for
security reasons. Since this deployment is for a single machine Kubernetes cluster,
run:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

1. Forking this repo

   Since this repo is a test and not yet hosted by the org, you will need to fork
   your own in order to make changes and authenticate using the flux agent.

2. Cloning the forked repo

   To use fluxCD and make changes to the application, you will need to clone the repo
   on the server node.

   ```bash
   git clone <fork-user>/k8s-firehose.git
   ```

3. Creating the authentication secrets

   The `flux bootstrap` command will need a secret GitHub personal token wity repo permissions
   in order to link the deployment to the cluster. If you don't currently have one, you will need
   to create one following [these instructions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

   After creating the token, you will need to export it to an env var for flux to use.
   You will also need to export your GitHub username.

   ```bash
   export GITHUB_USER=#YOUR-GITHUB-USERNAME
   export GITHUB_TOKEN=#YOUR-GITHUB-TOKEN
   ```

4. Bootstrapping the cluster

   After creating the auth secrets, you will be able to bootstrap the cluster.
   `cd` into the cloned repo and run this command:

   ```bash
   flux bootstrap github \
       --components-extra=image-reflector-controller,image-automation-controller \
       --owner=$GITHUB_USER \
       --repository=k8s-firehose \
       --branch=main \
       --path=clusters/k8s-firehose \
       --personal \
       --read-write-key
   ```

5. Are we there yet?

   **YES!**

   You should have a working cluster and the fireeth app deployed automatically if you
   followed these instructions.
