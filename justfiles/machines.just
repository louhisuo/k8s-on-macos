machine_topology := lowercase(env('TOPOLOGY'))
cp_cpu := env('CONTROLPLANE_CPU')
cp_ram := env('CONTROLPLANE_RAM')
cp_disk := env('CONTROLPLANE_DISK')
wn_cpu := env('WORKERNODE_CPU')
wn_ram := env('WORKERNODE_RAM')
wn_disk := env('WORKERNODE_DISK')

# Creates and starts machines used by different kubernetes cluster topologies
[group('machines')]
create:
    #!/usr/bin/env bash
    set -eux pipefail
    if [ {{ machine_topology }} == "minimal" ]; then
        limactl create machines/k8s-cp-machine.yaml --name cp-1 --cpus {{cp_cpu}} --memory {{cp_ram}} --disk {{cp_disk}} --set='.networks[].macAddress="52:55:55:12:34:01"' --tty=false
        limactl create machines/k8s-worker-machine.yaml --name worker-1 --cpus {{wn_cpu}} --memory {{wn_ram}} --disk {{wn_disk}} --set='.networks[].macAddress="52:55:55:12:34:04"' --tty=false
        limactl start cp-1 --tty=false
        limactl start worker-1 --tty=false
    elif [ {{ machine_topology }} == "non-ha" ]; then
        limactl create machines/k8s-cp-machine.yaml --name cp-1 --cpus {{cp_cpu}} --memory {{cp_ram}} --disk {{cp_disk}} --set='.networks[].macAddress="52:55:55:12:34:01"' --tty=false
        limactl create machines/k8s-worker-machine.yaml --name worker-1 --cpus {{wn_cpu}} --memory {{wn_ram}} --disk {{wn_disk}} --set='.networks[].macAddress="52:55:55:12:34:04"' --tty=false
        limactl create machines/k8s-worker-machine.yaml --name worker-2 --cpus {{wn_cpu}} --memory {{wn_ram}} --disk {{wn_disk}} --set='.networks[].macAddress="52:55:55:12:34:05"' --tty=false
        limactl create machines/k8s-worker-machine.yaml --name worker-3 --cpus {{wn_cpu}} --memory {{wn_ram}} --disk {{wn_disk}} --set='.networks[].macAddress="52:55:55:12:34:06"' --tty=false
        limactl start cp-1 --tty=false
        limactl start worker-1 --tty=false
        limactl start worker-2 --tty=false
        limactl start worker-3 --tty=false
    elif [ {{ machine_topology }} == "ha" ]; then
        limactl create machines/k8s-cp-machine.yaml --name cp-1 --cpus {{cp_cpu}} --memory {{cp_ram}} --disk {{cp_disk}} --set='.networks[].macAddress="52:55:55:12:34:01"' --tty=false
        limactl create machines/k8s-cp-machine.yaml --name cp-2 --cpus {{cp_cpu}} --memory {{cp_ram}} --disk {{cp_disk}} --set='.networks[].macAddress="52:55:55:12:34:02"' --tty=false
        limactl create machines/k8s-cp-machine.yaml --name cp-3 --cpus {{cp_cpu}} --memory {{cp_ram}} --disk {{cp_disk}} --set='.networks[].macAddress="52:55:55:12:34:03"' --tty=false
        limactl create machines/k8s-worker-machine.yaml --name worker-1 --cpus {{wn_cpu}} --memory {{wn_ram}} --disk {{wn_disk}} --set='.networks[].macAddress="52:55:55:12:34:04"' --tty=false
        limactl create machines/k8s-worker-machine.yaml --name worker-2 --cpus {{wn_cpu}} --memory {{wn_ram}} --disk {{wn_disk}} --set='.networks[].macAddress="52:55:55:12:34:05"' --tty=false
        limactl create machines/k8s-worker-machine.yaml --name worker-3 --cpus {{wn_cpu}} --memory {{wn_ram}} --disk {{wn_disk}} --set='.networks[].macAddress="52:55:55:12:34:06"' --tty=false
        limactl start cp-1 --tty=false
        limactl start cp-2 --tty=false
        limactl start cp-3 --tty=false
        limactl start worker-1 --tty=false
        limactl start worker-2 --tty=false
        limactl start worker-3 --tty=false
    else
        echo 'Non supported Kubernetes cluster topology {{ RED }}<{{ machine_topology }}>{{ NORMAL }}'
    fi

# Gracefully stops all currently running machines
[group('machines')]
stop:
    -limactl stop worker-3
    -limactl stop worker-2
    -limactl stop worker-1
    -limactl stop cp-3
    -limactl stop cp-2
    -limactl stop cp-1

# Force deletes all running and stopped machines
[group('machines')]
delete:
    -limactl delete worker-3 --force
    -limactl delete worker-2 --force
    -limactl delete worker-1 --force
    -limactl delete cp-3 --force
    -limactl delete cp-2 --force
    -limactl delete cp-1 --force

# Lists provisioned machines
[group('machines')]
list:
    limactl list