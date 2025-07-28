## Create Machines for Different Kubernetes Cluster Topologies
Use this guide if you want to create machines manually.

### Single Control Plane Node and Single Worker Node Topology
Create machines (Virtual Machines (VM) for nodes) for single Control Plane (CP) and Single Worker node cluster topology.
```
limactl create --set='.networks[].macAddress="52:55:55:12:34:01"' --name cp-1 machines/ubuntu-lts-machine.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:04"' --name worker-1 machines/ubuntu-lts-machine.yaml --tty=false
```

Start machines. 
```
limactl start cp-1
limactl start worker-1
```

### Single Control Plane Node and Three Worker Node Topology
Additional steps. Skip this step for single Worker Node cluster topology.

Create two additional machines (Virtual Machines (VM) for nodes) for three Worker Nodes cluster topology.
```
limactl create --set='.networks[].macAddress="52:55:55:12:34:05"' --name worker-2 machines/ubuntu-lts-machine.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:06"' --name worker-3 machines/ubuntu-lts-machine.yaml --tty=false
```

Start machines. 
```
limactl start worker-2
limactl start worker-3
```

### HA Control Plane and Three Worker Node Topology
Additional steps. Skip this step for single Control Plane cluster topology.

Create two additional machines for Control Plane (CP) nodes to implement HA cluster topology.
```
limactl create --set='.networks[].macAddress="52:55:55:12:34:02"' --name cp-2 machines/ubuntu-lts-machine.yaml --tty=false
limactl create --set='.networks[].macAddress="52:55:55:12:34:03"' --name cp-3 machines/ubuntu-lts-machine.yaml --tty=false
```

Start machines.
```
limactl start cp-2
limactl start cp-3
```