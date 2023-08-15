#!/bin/sh

# Exporting env var for flux bootstrap
export GITHUB_USER=$(cat ./secrets/github_account)
export GITHUB_TOKEN=$(cat ./secrets/github_token)

kind create cluster

# Creating the load balancer
kubectl apply -f ./infra/metallb
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=120s
kubectl apply -f ./infra/metallb/components

# Bootstrapping flux on the cluster
flux bootstrap github \
    --components-extra=image-reflector-controller,image-automation-controller \
    --owner=$GITHUB_USER \
    --repository=k8s-firehose \
    --branch=main \
    --path=clusters/k8s-firehose \
    --personal \
    --read-write-key
