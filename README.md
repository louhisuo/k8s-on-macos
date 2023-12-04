# Kubernetes on macOS (Apple silicon)

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
Kubernetes API server is available via VIP address `192.168.105.100`

#### Kubernetes L4 load balancer IP address pool
To access services from host address pool for L4 load balancer needs to be configured to same shared subnet than node IPs. Therefore we will use `192.168.105.240/28` as L4 load balancer address pool giving us 14 usable addresses. IP address `192.168.105.241` will be assigned for Ingress Controller.

#### Troubleshooting `socket_vmnet` related issues
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
limactl create --set='.networks[].macAddress="52:55:55:12:34:01"' --name cp-1 machines/ubuntu-machine-tmpl.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:04"' --name worker-1 machines/ubuntu-machine-tmpl.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:05"' --name worker-2 machines/ubuntu-machine-tmpl.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:06"' --name worker-3 machines/ubuntu-machine-tmpl.yaml --tty=false
```

Create machines for other Control Plane (CP) nodes to implement HA cluster configuration.
```
limactl create --set='.networks[].macAddress="52:55:55:12:34:02"' --name cp-2 machines/ubuntu-machine-tmpl.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:03"' --name cp-3 machines/ubuntu-machine-tmpl.yaml --tty=false
```

Please note that machine template file provisions components of the latest Kubernetes release.

Start machines for single Control Plane (CP) configuration. 
```
limactl start cp-1
limactl start worker-1
limactl start worker-2
limactl start worker-3
```

Start machines for other Control Plane (CP) nodes to implement HA cluster configuration.
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

Copy `kubeadm` config files into the other Control Plane (CP) node machines to implement HA cluster configuration.
```
limactl cp manifests/kubeadm/cp-2-join-cfg.yaml cp-2:
limactl cp manifests/kubeadm/cp-3-join-cfg.yaml cp-3:
```


### Setup single Control Plane (CP) Kubernetes cluster with three worker nodes

#### Initiate Kubernetes Control Plane (CP) in CP-1 machine
Following steps are to be run inside of `cp-1` machine

Generate `kube-vip` static pod manifest
```
export KVVERSION=v0.6.3
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
    --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

Initiate Kubernetes Control Plane (CP)
```
sudo kubeadm init --upload-certs --config cp-1-init-cfg.yaml
```

Copy `kubeconfig` for use by a regular user
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Install Gateway API bundle with experimental resources support. For details, see [Gatewway API project](https://gateway-api.sigs.k8s.io/guides/)
```
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/experimental-install.yaml
```

Install CNI (Cilium) with L2 load balancer, Ingress Controller and Gateway API support enabled.
```
cilium install --version 1.14.4 \
    --set operator.replicas=1 \
    --set ipam.operator.clusterPoolIPv4PodCIDRList="10.244.0.0/16" \
    --set kubeProxyReplacement=true \
    --set l2announcements.enabled=true \
    --set ingressController.enabled=true \
    --set ingressController.default=true \
    --set ingressController.loadbalancerMode=shared \
    --set ingressController.service.loadBalancerIP="192.168.105.241" \
    --set gatewayAPI.enabled=true
```
Note: `cilium status` will show TLS error until `kubelet serving` certificates are approved.

#### Setup `kubeconfig` on macOS host
Following steps are to be run on `macOS` host

Export `kubeconfig` from a CP node to host.
```
limactl cp cp-1:.kube/config ~/.kube/config.k8s-on-macos
```

Set context to freshly created Kubernetes cluster
```
export KUBECONFIG=~/.kube/config.k8s-on-macos 
```

Test that you are able to access the cluster from macOS host
```
kubectl version
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
Following steps are to be run inside of `cp-2`  machine`

Generate `kube-vip` static pod manifest
```
export KVVERSION=v0.6.3
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
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
export KVVERSION=v0.6.3
export INTERFACE=lima0
export VIP=192.168.105.100
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest pod \
    --arp \
    --controlplane \
    --address $VIP \
    --interface $INTERFACE \
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


### Manual approval of `kubelet serving` certificates
Approve any pending `kubelet-serving` certificate
```
kubectl get csr
kubectl get csr | grep "Pending" | awk '{print $1}' | xargs kubectl certificate approve
```

### Install add-ons
#### Metrics server
Install metrics server
```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Finalize initial configuration
Apply address pool configuration for L2 loadbalancer
```
kubectl apply -f manifests/cilium/l2-aware-lb-cfg.yaml
```

### Finals checks

Check from `macOS` host that cluster works as expected
```
kubectl version
cilium status
kubectl get nodes -o wide
kubectl get all -A -o wide
kubectl top nodes
kubectl top pods -A --sort-by=memory
```
--- END ---