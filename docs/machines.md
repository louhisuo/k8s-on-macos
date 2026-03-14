## Create Machines for Different Kubernetes Cluster Topologies
Use this guide if you want to create machines manually.

### Set Kubernetes release to be provisioned into machines
Modify 'machines/k8s-release.yaml' according to kubernetes version you plan to use.

### Single Control Plane Node and Single Worker Node Topology
Create machines (Virtual Machines (VM) for nodes) for single Control Plane (CP) and Single Worker node cluster topology.
```
limactl create machines/k8s-cp-machine.yaml --name cp-1 --set='.networks[].macAddress="52:55:55:12:34:01"' --tty=false
limactl create machines/k8s-worker-machine.yaml --name worker-1 --set='.networks[].macAddress="52:55:55:12:34:04"' --tty=false
```
Note: Use optional flags --memory and --disk to increase worker nodes sizes per your needs.

Start machines. 
```
limactl start cp-1 --tty=false
limactl start worker-1 --tty=false
```

### Single Control Plane Node and Three Worker Node Topology
Additional steps. Skip this step for single Worker Node cluster topology.

Create two additional machines (Virtual Machines (VM) for nodes) for three Worker Nodes cluster topology.
```
limactl create machines/k8s-worker-machine.yaml --name worker-2 --set='.networks[].macAddress="52:55:55:12:34:05"' --tty=false
limactl create machines/k8s-worker-machine.yaml --name worker-3 --set='.networks[].macAddress="52:55:55:12:34:06"' --tty=false
```
Note: Use optional flags --memory and --disk to increase worker nodes sizes per your needs.

Start machines. 
```
limactl start worker-2 --tty=false
limactl start worker-3 --tty=false
```

### HA Control Plane and Three Worker Node Topology
Additional steps. Skip this step for single Control Plane cluster topology.

Create two additional machines for Control Plane (CP) nodes to implement HA cluster topology.
```
limactl create machines/k8s-cp-machine.yaml --name cp-2 --set='.networks[].macAddress="52:55:55:12:34:02"' --tty=false
limactl create machines/k8s-cp-machine.yaml --name cp-3 --set='.networks[].macAddress="52:55:55:12:34:03"' --tty=false
```

Start machines.
```
limactl start cp-2 --tty=false
limactl start cp-3 --tty=false
```