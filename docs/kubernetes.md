## Deploy Kubernetes Cluster with Different Kubernetes Cluster Topologies
Use this guide if you want to create Kubernetes clusters manually on previously deployed machines.

# Set Kubernetes release to be used in Kubernetes cluster
This step generates Kubernetes initialization configuration yaml file with Kubernetes version specified in k8s-on-macos.env
```
sed "s#<KUBERNETES_VERSION>#$(grep -e 'KUBERNETES_VERSION' k8s-on-macos.env | awk '{gsub(/[^.0-9]/, ""); printf "\"v%s\"",$1}')#g" manifests/kubeadm/cp-1-init-cfg.templ.yaml | tee manifests/kubeadm/cp-1-init-cfg.yaml >/dev/null
```


### Single Control Plane Node and Single Worker Node Topology

#### Prerequisites
Copy `kubeadm` config files into the machines.
```
limactl cp manifests/kubeadm/cp-1-init-cfg.yaml cp-1:
limactl cp manifests/kubeadm/worker-1-join-cfg.yaml worker-1:
```

#### Initiate Kubernetes Control Plane (CP) in CP-1 machine
Following steps are to be run inside of `cp-1` machine

Generate `kube-vip` static pod manifest
```
export KVVERSION=v0.9.2
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
    --enableLoadBalancer \
    --enableNodeLabeling \
    --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

Workaround for Kubernetes 1.29 and onward, until until bootstrap issue with `kube-vip` is fixed (Note: This step is only applicable with Kubernetes 1.29)
Patch `kube-vip.yaml` to use super-admin.conf during `kubeadm init`
```
sudo sed -i 's#path: /etc/kubernetes/admin.conf#path: /etc/kubernetes/super-admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml
```

Initiate Kubernetes Control Plane (CP)
```
sudo kubeadm init --upload-certs --config cp-1-init-cfg.yaml
```

Workaround for Kubernetes 1.29 and onwards, until until bootstrap issue with `kube-vip` is fixed (Note: This step is only applicable with Kubernetes 1.29)
Patch `kube-vip.yaml` to use admin.conf after `kubeadm init` has been successfully executed
```
sudo sed -i 's#path: /etc/kubernetes/super-admin.conf#path: /etc/kubernetes/admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml
```

#### Setup kubeconfig for a regular user on macOS host
Inside of `cp-1` machine copy `kubeconfig` for a regular user
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

On `macOS` host export and set `kubeconfig` for a regular user
```
limactl cp cp-1:.kube/config ~/.kube/config.k8s-on-macos
chown $(id -u):$(id -g) ~/.kube/config.k8s-on-macos
export KUBECONFIG=~/.kube/config.k8s-on-macos
```

#### Join worker nodes to Kubernetes cluster
Following steps are to be run inside of respective worker node machines

Join `worker-1`
```
sudo kubeadm join --config worker-1-join-cfg.yaml
```

### Single Control Plane Node and Three Worker Node Topology
Additional steps. Skip this step for single Worker Node cluster topology.

#### Prerequisites
Copy `kubeadm` config files into the machines.
```
limactl cp manifests/kubeadm/worker-2-join-cfg.yaml worker-2:
limactl cp manifests/kubeadm/worker-3-join-cfg.yaml worker-3:
```

#### Join worker nodes to Kubernetes cluster
Following steps are to be run inside of respective worker node machines

Join `worker-2`
```
sudo kubeadm join --config worker-2-join-cfg.yaml
```

Join `worker-3`
```
sudo kubeadm join --config worker-3-join-cfg.yaml
```

### High Available Control Plane Node and Three Worker Node Topology
Additional steps. Skip this step for single Control Plane cluster topology.

#### Prerequisites
Copy `kubeadm` config files into the machines.
```
limactl cp manifests/kubeadm/cp-2-join-cfg.yaml cp-2:
limactl cp manifests/kubeadm/cp-3-join-cfg.yaml cp-3:
```

#### Join other Control Plane (CP) nodes to implement High Available (HA) Kubernetes cluster
Following steps are to be run inside of `cp-2`  machine`. Skip these steps for single Control Plane Kubernetes cluster configuration.

Generate `kube-vip` static pod manifest
```
export KVVERSION=v0.9.2
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
    --enableLoadBalancer \
    --enableNodeLabeling \
    --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

Join additional Control Plane (CP) node
```
sudo kubeadm join --config cp-2-join-cfg.yaml
```

Copy `kubeconfig` for use by a regular user
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Following steps are to be run inside of `cp-3` node machine`

Generate `kube-vip` static pod manifest
```
export KVVERSION=v0.9.2
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
    --enableLoadBalancer \
    --enableNodeLabeling \
    --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

Join additional Control Plane (CP)
```
sudo kubeadm join --config cp-3-join-cfg.yaml
```

Copy `kubeconfig` for use by a regular user
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## Post Kubernetes Cluster Deployment Tasks

### Manual approval of kubelet serving certificates
Approve any pending `kubelet-serving` certificate
```
kubectl get csr
kubectl get csr | grep "Pending" | awk '{print $1}' | xargs kubectl certificate approve
```

### Cilium CNI
#### Install Gateway API Custom Resource Definitions
Install Gateway API CRDs supported by Cilium.
```
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/experimental-install.yaml
```

#### Install Cilium CNI
Install CNI (Cilium). See `values.yaml` for details what capabilities have been enabled.
```
export CILIUM_CHART_VERSION=1.17.6
helm repo add cilium https://helm.cilium.io/ --force-update
helm install cilium cilium/cilium \
     --version $CILIUM_CHART_VERSION \
     --namespace kube-system \
     --values manifests/cilium/values.yaml
```

Monitor that Cilium CNI status until deployment completed
```
cilium status --wait
```

### Install Flux
Install Flux operator
```
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
    --namespace flux-system \
    --create-namespace
```
