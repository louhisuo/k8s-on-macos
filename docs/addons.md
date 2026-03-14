## Install Kubernetes Add-ons
Use this guide if you want to install Kubernetes addons manually after you have deployed Kubernetes cluster.

After Kubernetes cluster deployment is completed, it is required to install some Kubernetes add-ons to make cluster useful.

### Install cert-manager
Install cert-manager
```
export CERTMANAGER_VERSION=1.19.3
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
    --version v${CERTMANAGER_VERSION} \
    --namespace cert-manager \
    --create-namespace \
    --values infra/cert-manager/controller/values.yaml
```

### Install Local path provisioner CSI
Install local path provisioner
```
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml

helm upgrade --install -n kube-system local-path-provisioner oci://ghcr.io/rancher/local-path-provisioner/charts/local-path-provisioner --version 0.0.34

export LOCALPATHPROVISIONER_VERSION=0.0.34
helm install local-path-provisioner oci://ghcr.io/rancher/local-path-provisioner/charts/local-path-provisioner \
    --version ${LOCALPATHPROVISIONER_VERSION} \
    --namespace local-path-provisioner \
    --create-namespace
```

### Install Metrics server
Install metrics server
```
export METRICS_SERVER_CHART_VERSION=3.13.0
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm install metrics-server metrics-server/metrics-server \
     --version $METRICS_SERVER_CHART_VERSION \
     --namespace kube-system \
     --values infra/metrics-server/controller/values.yaml
```

## Configure Kubernetes Add-ons
Note: This guide assumes that your DNS is properly configured to route traffic into and within Kubernetes cluster. How to setup and configure DNS is out of scope and I have no intention to document it here. My DNS is based on Mikrotik RouterOS. 

### Configure cert-manager
Create cluster issuer resource
```
kubectl apply -f infra/cert-manager/manifests/clusterissuer.yaml
```
### Configure Cilium CNI
Configure L2 announcements and default address pool for L2 aware LB
```
kubectl apply -f infra/cilium/manifests/ciliuml2announcementpolicy.yaml
kubectl apply -f infra/cilium/manifests/ciliumloadbalancerippool.yaml
```
Configure default Gateway resource
```
kubectl apply -f infra/cilium/manifests/gateway.yaml
```
### Configure local-path-provisioner
Apply local path provisioner configuration.
Note: There will be a delay after `configmap` is applied before the provisioner picks it up.
```
kubectl apply -f infra/local-path-provisioner/manifests/configmap.yaml
```
