#!/bin/bash
# delete kubeadm cluster
sudo kubeadm reset

# uninstall tools and configs
sudo apt-mark unhold kubelet kubeadm kubectl
sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni 'kube*' -y
sudo apt-get autoremove

# clean up left configs
sudo rm -rf ~/.kube
sudo rm -rf /etc/cni
sudo rm -rf /var/lib/cni
sudo rm -rf /var/lib/kubelet/*
sudo rm -rf /etc/systemd/system/kubelet.service.d

# clean up cilium routes
ip route | grep cilium | awk '{print $1}' | while read -r route; do sudo ip route del $route; done

# reboot needed
sudo reboot