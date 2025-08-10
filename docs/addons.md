## Install Kubernetes Add-ons
Use this guide if you want to install Kubernetes addons manually after you have deployed Kubernetes cluster.

After Kubernetes cluster deployment is completed, it is required to install some Kubernetes add-ons to make cluster useful.

### Install cert-manager
Install cert-manager
```
export CERT_MANAGER_CHART_VERSION=1.18.2
helm repo add jetstack https://charts.jetstack.io --force-update
helm install cert-manager jetstack/cert-manager \
     --version $CERT_MANAGER_CHART_VERSION \
     --namespace cert-manager \
     --create-namespace \
     --values manifests/cert-manager/values.yaml
```

### Install Local path provisioner CSI
Install local path provisioner
```
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
```

### Install Metrics server
Install metrics server
```
export METRICS_SERVER_CHART_VERSION=3.12.2
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm install metrics-server metrics-server/metrics-server \
     --version $METRICS_SERVER_CHART_VERSION \
     --namespace kube-system \
     --values manifests/metrics-server/values.yaml
```

## Configure Kubernetes Add-ons
Note: This guide assumes that your DNS is properly configured to route traffic into and within Kubernetes cluster. How to setup and configure DNS is out of scope and I have no intention to document it here. My DNS is based on Mikrotik RouterOS. 

### Configure cert-manager
Create cluster issuer resource
```
kubectl apply -f manifests/cert-manager/ca-clusterissuer.yaml
```
### Configure Cilium CNI
Configure L2 announcements and default address pool for L2 aware LB
```
kubectl apply -f manifests/cilium/l2-lb-cfg.yaml
```
Configure default Gateway resource
```
kubectl apply -f manifests/cilium/gateway-with-tls.yaml
```
### Configure local-path-provisioner
Apply local path provisioner configuration.
Note: There will be a delay after `configmap` is applied before the provisioner picks it up.
```
kubectl apply -f manifests/local-path-provisioner/provisioner-cm.yaml
```
