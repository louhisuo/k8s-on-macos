# Kubernetes on macOS (Apple silicon)
Note #1: `kube-vip` add-on is incompatible with Kubernetes 1.29 (see kube-vip github issue [#684](https://github.com/kube-vip/kube-vip/issues/684)). It is possible to get this setup working with Kubernetes 1.29.x by using a [workaround](https://github.com/kube-vip/kube-vip/issues/684#issuecomment-1864855405). This workaround has also been used in this guide.

## Project Goal
A fully functional multi-node Kubernetes cluster on macOS (Apple silicon) with support for both macOS Host - Virtual Machine (VM) and VM-VM communication with following cluster topologies.

Kubernetes cluster topologies available:
- Single Control Plane and single Worker node topology
- Single Control Plane and three Worker nodes topology
- High available Control Plane and three Worker nodes topology

## High-level Architecture
### HA Control Plan and three Worker nodes
![Network Architecture](diagrams/network.drawio.png)

## Current Components
### Host, Virtualization and Machines
- Host: macOS 15.5 (Sequoia)
- Virtualization: Lima VM 1.2.0 / socket_vmnet 1.2.1
- Node images: (machines) Ubuntu 24.04 LTS
### Kubernetes and Add-ons
- Kubernetes 1.33.3
- kube-vip 0.9.2 (used as Kubernetes HA Control Plane LB)
- Cilium 1.17.6 (used as CNI, L2 LB (ARP), L7 LB (Kubernetes Ingress Controller) and L4/L7 LB (Gateway API))
- Gateway API 1.2.1 (Based on Cilium CNI implementation)
- metrics-server 0.7.2 (helm chart version 3.12.1)
- local-path-provisioner 0.0.31

Note: File `k8s-on-macos.env` specifies Kubernetes and its addons releases to be used when deploying a Kubernetes cluster by using Taskfile automation which is a new default way to deploy different cluster topologies.

## Networking
Network must be available prior deploying different Kubernetes cluster topologies. Shared network with subnet `192.168.105.0/24` is used as it allows both Host-VM and VM-VM communication. From this shared network we use IP address range from `192.168.105.100` and onward in our Kubernetes cluster. 

### Allocated Kubernetes node IPs
Following static IP addresses will be reserved as static node IPs in a Kubernetes cluster after shared network installation procedure is completed. 
| Host     | MAC Address       | IP address      | Comments                                    |
| -------- | ----------------- | --------------- | ------------------------------------------- |
| cp       | 52:55:55:12:34:00 | 192.168.105.100 | Control Plane (CP) Virtual IP (VIP) address |
| cp-1     | 52:55:55:12:34:01 | 192.168.105.101 |                                             |
| cp-2     | 52:55:55:12:34:02 | 192.168.105.102 | Additional CP node in HA CP cluster.        |
| cp-3     | 52:55:55:12:34:03 | 192.168.105.103 | Additional CP node in HA CP cluster.        |
| worker-1 | 52:55:55:12:34:04 | 192.168.105.104 |                                             |
| worker-2 | 52:55:55:12:34:05 | 192.168.105.105 |                                             |
| worker-3 | 52:55:55:12:34:06 | 192.168.105.106 |                                             |
### Kubernetes API server
Kubernetes API server is available via VIP address `192.168.105.100` and `sandbox-api.k8s.internal` is used as FQDN for Kubernetes API server.

### L2 Aware load balancer, Ingress and Gateway
IP address pool for `Load Balancer` services must be configured to same shared subnet than Kubernetes cluster `node IPs`. Currently L2 Aware LB in Cilium CNI is used and default address pool is configured with address range `192.168.105.240 - 192.168.105.254`.

From the assigned address pool following IPs are "reserved" for default Kubernetes Ingress and Gateway API.
- `192.168.105.254` is assigned to `Ingress` resource `sandbox-ingress.k8s.internal` and
- `192.168.105.253` is assigned to shared `Gateway` resource `sandbox-gtw.k8s.internal`.

Note: From Cilium CNI release 1.17.x and onwards. Cilium implementation supports static IP assignments for `Gateway` resources.

## Storage
Used storage provisioner `local-path-provisioner` requires a storage path to be provisioned for its use on macOS host and exposed to a Kubernetes cluster through machine VMs.

This project assumes that a directory `/opt/lima` is available prior deploying different Kubernetes cluster topologies.

## Prerequisites
### Git Repository (this project)
Git repo has been cloned to local macOS host. All commands will be executed from repo root folder unless stated otherwise.

### Required Tools
Following tools are minimal requirements by this project. [Homebrew](https://brew.sh/) is used to install these tools on macOS host.
- [ ] [Lima VM](https://github.com/lima-vm/lima)
- [ ] [socket_vmnet](https://github.com/lima-vm/socket_vmnet/)
- [ ] [kubernetes-cli](https://github.com/kubernetes/kubectl)
- [ ] [cilium-cli](https://github.com/cilium/cilium-cli/)
- [ ] [helm](https://helm.sh/)
- [ ] [Git](https://git-scm.com/)

### Install tools
This step is required only to be executed once, prior deploying your first Kubernetes cluster topology.

Install `Homebrew`. After install is completed, follow a prompt for additional steps.
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install `Taskfile`
```
brew install go-task/tap/go-task
```

Install tools
```
task brew:install
```

### Provisioning of networking
This step is required only to be executed once, prior deploying your first Kubernetes cluster topology.

#### Install socket_vmnet
Per Lima VM networking documentation, Homebrew installation method is not recommended for `socket_vmnet`. Therefore alternative install method is used.

Install socket_vmnet binary from tar.gz archive file
```
VERSION="$(curl -fsSL https://api.github.com/repos/lima-vm/socket_vmnet/releases/latest | jq -r .tag_name)"
FILE="socket_vmnet-${VERSION:1}-$(uname -m).tar.gz"
curl -OSL "https://github.com/lima-vm/socket_vmnet/releases/download/${VERSION}/${FILE}"
sudo tar Cxzvf / "${FILE}" opt/socket_vmnet
```

#### Prepare macOS DHCP service
DHCP service in macOS host must be prepared to handover predefined static IP addresses based on MAC addresses to be assigned on machine VMs vNIC interface.

Populate DHCP configuration database on macOS host. Please note that per these instructions any possible previous DHCP configuration DB will be overwritten.
```
sudo cp macos/etc/bootptab /etc/.
```
Start macOS DHCP server and load its configuration DB
```
sudo /bin/launchctl load -w /System/Library/LaunchDaemons/bootps.plist
sudo /bin/launchctl kickstart -kp system/com.apple.bootpd
```

#### Prepare Lima VM shared networking configuration
Create networking configuration for Lima VM
```
mkdir -p ~/.lima/_config
cp macos/home/.lima/_config/networks.yaml ~/.lima/_config/.
```

#### Prepare sudoers file
Setup sudoers file to launch socket_vmnet from Lima VM
```
limactl sudoers | sudo tee /etc/sudoers.d/lima
```

#### For reference
- https://github.com/lima-vm/socket_vmnet?tab=readme-ov-file#from-binary
- https://lima-vm.io/docs/config/network/vmnet/#socket_vmnet

### Provisioning of storage paths
This step is required only to be executed once, prior deploying your first Kubernetes cluster topology.

Create storage path on macOS host for kubeconfig files
```
mkdir -p ~/.kube
chmod 700 ~/.kube
```

Create storage path on macOS host and make it world writable (this is not secure)
```
sudo mkdir -p /opt/lima
sudo chmod 777 /opt/lima
```

## Create Machines for Different Kubernetes Cluster Topologies
Machine life cycle for different Kubernetes cluster topologies is now automated by using Taskfile. With automation it is possible to provision machines for a specified Kubernetes cluster topology, stop all machines in a specified cluster topology and force delete all running or stopped machines in a specified cluster topology.

Supported Kubernetes cluster topologies are
- Single Control Plane Node and Single Worker Node topology (minimal)
- Single Control Plane Node and Three Worker Nodes topology (non-ha) and
- Three Control Plane Nodes and Three Worker Nodes topology (ha)

How to use
- To provision machines use task runner `task provision-machines -- <minimal | non-ha | ha>
- To stop machines use task runner `task stop-machines -- <minimal | non-ha | ha>
- To force delete machines use task runner `task delete-machines -- <minimal | non-ha | ha>
- Modify environment variables in the file `machines.env` to adjust Worker Nodes CPUs, Memory and Disk

### Single Control Plane Node and Single Worker Node Topology
```
task machines:bootstrap -- minimal
```

### Single Control Plane Node and Three Worker Nodes Topology
```
task machines:bootstrap -- non-ha
```

### Three Control Plane Nodes and Three Worker Nodes Topology
```
task machines:bootstrap -- ha
```

## Deploy Kubernetes Cluster with Different Kubernetes Cluster Topologies
Creation of creating Kubernetes cluster with different topologies is now automated by using Taskfile.

### Single Control Plane Node and Single Worker Node Topology
```
task kubernetes:bootstrap -- minimal
```

### Single Control Plane Node and Three Worker Nodes Topology
```
task kubernetes:bootstrap -- non-ha
```

### Three Control Plane Nodes and Three Worker Nodes Topology
```
task kubernetes:bootstrap -- ha
```

## Finals checks
Check from that cluster works as expected
```
kubectl version
cilium status
kubectl get --raw='/readyz?verbose'
```

## Deploy Kubernetes Add-ons (optional)
After Kubernetes cluster deployment is succesfully completed, it is beneficial to install some Kubernetes add-ons to make cluster more useful.
```
task addons:bootstrap
```

## Install Applications (optional)
### Install Headlamp Kubernetes WebUI
Headlamp Kubernetes WebUI is a handy way visualize Kubernetes clusters. Installing Headlamp can also be used to confirm that LB, Ingress and Gateway API work as expected.

I am transitioning to use Gateway API in my personal projects this Headlamp WebUI application will be only one where Kubernetes Ingress resource example will be made available.

Install Headlamp
```
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp --force-update
helm install headlamp headlamp/headlamp \
     --namespace headlamp \
     --create-namespace \
     -f manifests/headlamp/values.yaml
```
If Headlamp is accessed through Gateway API, apply this HTTProute manifest
```
kubectl apply -f manifests/headlamp/httproute.yaml
```
If Headlamp is accessed through Kubernetes Ingress, apply this Ingress manifest
```
kubectl apply -f manifests/headlamp/ingress.yaml
```
Generate access token for Headlamp
```
kubectl create token headlamp --namespace kube-system
```
Access Headlamp WebUI through one of following URLs by using above generated token to authenticate. In case of issues, check your Web Browser and DNS settings.
```
With Gateway API, use
https://headlamp.sandbox.k8s.internal/

With Kubernetes Ingress, use
https://headlamp-ingress.sandbox.k8s.internal/
```

## Miscellaneous Helpful Hints

### Proxying API server to macOS host
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

### Exposing services via NodePort to macOS host
It is possible to expose Kubernetes services via `NodePort` to `macOS` host. Full `NodePort` range `30000-32767` is exposed to `macoS` host from provisioned `Lima VM` machines during machine creation phaase.

Actual services with `type: NodePort` will be available on `macOS` host via `node IP` address of any Control Plane or Worker nodes of a cluster (not via VIP address) and assigned `NodePort` value for a service.

### Troubleshooting socket_vmnet related issues
Update sudoers config and _config/networks.yaml file.
Currently it is neccessary to replace `socketVMNet` field in `~/.lima/_config/networks.yaml` with absolute path, instead of symbolic link and generate sudoers configuration to able to execute `limactl start`.

After `socket_vmnet` is upgraded, it is neccessary to adjust the absolute path in `networks.yaml` and regenerate sudoers configuration with
```
limactl sudoers >etc_sudoers.d_lima && sudo install -o root etc_sudoers.d_lima "/private/etc/sudoers.d/lima"
```
--- END ---