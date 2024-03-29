# Kubernetes on macOS (Apple silicon)
Kubernetes release now defaults to 1.28.6 release !!
Note that `kube-vip` is incompatible with Kubernetes 1.29 (see issues in Github). It is possible to get this setup working with Kubernetes 1.29 by using kube-vip 0.6.3 with some workarounds. However setup is not very stable.

## Goals
Setup a fully functional multi-node Kubernetes cluster on macOS (Apple silicon) with both Host-VM and VM-VM communication.

## Prerequisites

### Tools
Homebrew will be used to install all tools needed on macOS host.
- [ ] [Homebrew](https://brew.sh/)
- [ ] [Git](https://git-scm.com/)
- [ ] [Lima VM](https://github.com/lima-vm/lima)
- [ ] [socket_vmnet](https://github.com/lima-vm/socket_vmnet/)
- [ ] [cilium-cli](https://github.com/cilium/cilium-cli/)
- [ ] [kubectl](https://github.com/kubernetes/kubectl)
- [ ] [helm](https://helm.sh/)

### Current default versions
- Lima VM 0.20.1 / socket_vmnet 1.1.4 - Virtualization
- Ubuntu 22.04 LTS - Node images
- Kubernetes 1.28.6 - Kubernetes release
- Cilium 1.15.1 - CNI, L2 LB, L7 LB (Ingress Controller) and L4/L7 LB (Gateway API)
- Gateway API 1.0 - CRDs supported by Cilium 1.15.1
- kube-vip 0.6.3. - Kubernetes Control Plane LB
- metrics-server 0.7.0
- local-path-provisioner 0.0.26

### Assumptions
Git repo has been cloned to local macOS hosts. All commands are to be executed from repo root on host, unless stated otherwise.

### Kubernetes cluster configurations
- Single Control Plane and Three worker nodes Kubernetes cluster (execute steps for single Control Plane (CP) cluster configuration)
- High Available (HA) Control Plane Kubernetes cluster with Three Control Plane and Three Worker nodes (execute all steps)

### Networking
Shared network `192.168.105.0/24` in macOS is used as it allows both Host-VM and VM-VM communication. By default Lima VM uses DHCP range until `192.168.105.99` therefore we use IP address range from `192.168.105.100` and onward in our Kubernetes setup. To have predictable node IPs for a Kubernetes cluster, it is neccessary to [reserve IPs](https://github.com/lima-vm/socket_vmnet#how-to-reserve-dhcp-addresses) to be used from DHCP server in macOS.

#### Kubernetes node IP range
Define following [/etc/bootptab](macos/etc/bootptab) file.
| Host     | MAC Address       | IP address      | Comments                                    |
| -------- | ----------------- | --------------- | ------------------------------------------- |
| cp       | 52:55:55:12:34:00 | 192.168.105.100 | Control Plane (CP) Virtual IP (VIP) address |
| cp-1     | 52:55:55:12:34:01 | 192.168.105.101 |                                             |
| cp-2     | 52:55:55:12:34:02 | 192.168.105.102 | Additional CP node in HA CP cluster.        |
| cp-3     | 52:55:55:12:34:03 | 192.168.105.103 | Additional CP node in HA CP cluster.        |
| worker-1 | 52:55:55:12:34:04 | 192.168.105.104 |                                             |
| worker-2 | 52:55:55:12:34:05 | 192.168.105.105 |                                             |
| worker-3 | 52:55:55:12:34:06 | 192.168.105.106 |                                             |

Reload macOS DHCP daeamon.
```
sudo /bin/launchctl kickstart -kp system/com.apple.bootpd
```
#### Kubernetes API server
Kubernetes API server is available via VIP address `192.168.105.100`.

#### L2 Aware load balancer, Ingress and Gateway
IP address pool for `Load Balancer` services must be configured to same shared subnet than cluster `node IPs`. Currently L2 Aware LB in Cilium CNI is used and default address pool is configured is `192.168.105.240/28`.

From the assigned address pool following IPs are "reserved", leaving 12 addresses available for different LB services.
- `192.168.105.241` is assigned to `Ingress` (Cilium Ingress Controller) and
- `192.168.105.242` is reserved for `Gateway` (Cilium Gateway API). `Gateway` configuration is work in progress.

#### Proxying API server to macOS host
Inside a `Control Plane` node, start HTTP proxy for Kubernetes API.
```
kubectl --kubeconfig $HOME/.kube/config proxy
```

Or on `macOS` host, start HTTP proxy for Kubernetes API.
```
kubectl --kubeconfig ~/.kube/config.k8s-on-macos proxy
```


Access Kubernetes API from `macOS` host using `curl`, `wget` or any `web browser` using following URL.
```
http://localhost:8001/api/v1
```

#### Exposing services via NodePort to macOS host
It is possible to expose Kubernetes services via `NodePort` to `macOS` host. Full `NodePort` range `30000-32767` is exposed to `macoS` host from provisioned `Lima VM` machines during machine creation phaase.

Actual services with `type: NodePort` will be available on `macOS` host via `node IP` address of any Control Plane or Worker nodes of a cluster (not via VIP address) and assigned `NodePort` value for a service.

#### Troubleshooting socket_vmnet related issues
Update sudoers config and _config/networks.yaml file.
Currently it is neccessary to replace `socketVMNet` field in `~/.lima/_config/networks.yaml` with absolute path, instead of symbolic link and generate sudoers configuration to able to execute `limactl start`.

After `socket_vmnet` is upgraded, it is neccessary to adjust the absolute path in `networks.yaml` and regenerate sudoers configuration with
```
limactl sudoers >etc_sudoers.d_lima && sudo install -o root etc_sudoers.d_lima "/private/etc/sudoers.d/lima"
```

## Provision machines for Kubernetes
[Lima VM](https://github.com/lima-vm/lima) is used to provision machines for Kubernetes.

Create machines (Virtual Machines (VM) for nodes) for single Control Plane (CP) cluster configuration. 
```
limactl create --set='.networks[].macAddress="52:55:55:12:34:01"' --name cp-1 machines/ubuntu-lts-machine.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:04"' --name worker-1 machines/ubuntu-lts-machine.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:05"' --name worker-2 machines/ubuntu-lts-machine.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:06"' --name worker-3 machines/ubuntu-lts-machine.yaml --tty=false
```

Create machines for other Control Plane (CP) nodes to implement HA cluster configuration. Skip this step for single Control Plane Kubernetes cluster configuration.
```
limactl create --set='.networks[].macAddress="52:55:55:12:34:02"' --name cp-2 machines/ubuntu-lts-machine.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:03"' --name cp-3 machines/ubuntu-lts-machine.yaml --tty=false
```

Please note that machine template file provisions components of the latest Kubernetes release.

Start machines for single Control Plane (CP) configuration. 
```
limactl start cp-1
limactl start worker-1
limactl start worker-2
limactl start worker-3
```

Start machines for other Control Plane (CP) nodes to implement HA cluster configuration. Skip this step for single Control Plane Kubernetes cluster configuration.
```
limactl start cp-2
limactl start cp-3
```

Check that all all machines are running
```
limactl list
```


## Initiate Kubernetes cluster

### Prerequisites
Copy `kubeadm` config files into the machines for single Control Plane (CP) configuration.
```
limactl cp manifests/kubeadm/cp-1-init-cfg.yaml cp-1:
limactl cp manifests/kubeadm/worker-1-join-cfg.yaml worker-1:
limactl cp manifests/kubeadm/worker-2-join-cfg.yaml worker-2:
limactl cp manifests/kubeadm/worker-3-join-cfg.yaml worker-3:
```

Copy `kubeadm` config files into the other Control Plane (CP) node machines to implement HA cluster configuration. Skip this step for single Control Plane Kubernetes cluster configuration.
```
limactl cp manifests/kubeadm/cp-2-join-cfg.yaml cp-2:
limactl cp manifests/kubeadm/cp-3-join-cfg.yaml cp-3:
```


### Setup single Control Plane (CP) Kubernetes cluster with three worker nodes
#### Initiate Kubernetes Control Plane (CP) in CP-1 machine
Following steps are to be run inside of `cp-1` machine

Generate `kube-vip` static pod manifest
```
export KVVERSION=v0.7.1
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
    --enableLoadBalancer \
    --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

Workaround for Kubernetes 1.29, until until bootstrap issue with `kube-vip` is fixed (Note: This step is only applicable with Kubernetes 1.29)
Patch `kube-vip.yaml` to use super-admin.conf during `kubeadm init`
```
sudo sed -i 's#path: /etc/kubernetes/admin.conf#path: /etc/kubernetes/super-admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml
```

Initiate Kubernetes Control Plane (CP)
```
sudo kubeadm init --upload-certs --config cp-1-init-cfg.yaml
```

Workaround for Kubernetes 1.29, until until bootstrap issue with `kube-vip` is fixed (Note: This step is only applicable with Kubernetes 1.29)
Patch `kube-vip.yaml` to use admin.conf after `kubeadm init` has been successfully executed
```
sudo sed -i 's#path: /etc/kubernetes/super-admin.conf#path: /etc/kubernetes/admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml
```

#### Setup kubeconfig for a regular user
Inside of `cp-1` machine copy `kubeconfig` for a regular user
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

On `macOS` host export and set `kubeconfig` for a regular user
```
limactl cp cp-1:.kube/config ~/.kube/config.k8s-on-macos
export KUBECONFIG=~/.kube/config.k8s-on-macos
```

#### Join worker nodes to Kubernetes cluster
Following steps are to be run inside of respective worker node machines

Join `worker-1`
```
sudo kubeadm join --config worker-1-join-cfg.yaml
```

Join `worker-2`
```
sudo kubeadm join --config worker-2-join-cfg.yaml
```

Join `worker-3`
```
sudo kubeadm join --config worker-3-join-cfg.yaml
```


### Join other Control Plane (CP) nodes to implement High Available (HA) Kubernetes cluster
Following steps are to be run inside of `cp-2`  machine`. Skip these steps for single Control Plane Kubernetes cluster configuration.

Generate `kube-vip` static pod manifest
```
export KVVERSION=v0.7.1
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
    --enableLoadBalancer \
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
export KVVERSION=v0.7.1
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
    --enableLoadBalancer \
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

### Manual approval of kubelet serving certificates
Approve any pending `kubelet-serving` certificate
```
kubectl get csr
kubectl get csr | grep "Pending" | awk '{print $1}' | xargs kubectl certificate approve
```

### Install Gateway API
Install Gateway API CRDs supported by Cilium.
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/experimental/gateway.networking.k8s.io_grpcroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
```

### Install and configure Cilium CNI
Install CNI (Cilium) with L2 LB, L7 LB (Ingress Controller) and L4/L7 LB (Gateway API) support enabled.
```
export CILIUM_VERSION=1.15.1
helm install cilium cilium/cilium --version $CILIUM_VERSION --namespace kube-system --values manifests/cilium/values.yaml
```

Configure L2 announcements and address pool for L2 aware Load Balancer
```
kubectl apply -f manifests/cilium/l2-lb-cfg.yaml
```

Configure Gateway (default)
```
kubectl apply -f manifests/cilium/gtw-cfg.yaml
```

## Install add-ons
### Metrics server
Install metrics server
```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Local path provisioner
Install local path provisioner
```
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
```

Apply local path provisioner configuration. There will be a delay after `configmap` is applied before the provisioner picks it up.
```
kubectl apply -f manifests/local-path-provisioner/provisioner-cm.yaml
```


## Finals checks
Check from that cluster works as expected
```
kubectl version
cilium status
kubectl get --raw='/readyz?verbose'
```
--- END ---
