kubernetes_topology := lowercase(env('TOPOLOGY'))
gatewayapi_version := env('GATEWAYAPI_VERSION')
cilium_version := env('CILIUM_VERSION')
fluxoperator_version := env('FLUXOPERATOR_VERSION')

# Generates kubeadm config files
[group('kubeadm')]
config-generate:
    kustomize build manifests/kubeadm/cp-1-init | tee manifests/kubeadm/out/cp-1-init-config.yaml
    kustomize build manifests/kubeadm/cp-2-join | tee manifests/kubeadm/out/cp-2-join-config.yaml
    kustomize build manifests/kubeadm/cp-3-join | tee manifests/kubeadm/out/cp-3-join-config.yaml
    kustomize build manifests/kubeadm/worker-1-join | tee manifests/kubeadm/out/worker-1-join-config.yaml
    kustomize build manifests/kubeadm/worker-2-join | tee manifests/kubeadm/out/worker-2-join-config.yaml
    kustomize build manifests/kubeadm/worker-3-join | tee manifests/kubeadm/out/worker-3-join-config.yaml

# Bootstraps Kubernetes cluster with specified topology
[group('kubernetes')]
bootstrap:
    #!/usr/bin/env bash
    set -eux pipefail
    if [ {{ kubernetes_topology }} == "minimal" ]; then
        just _init-cp-1
        just _join-worker-1
        just _copy-kubeconfig cp-1
        just _sign-csrs
        just _install-addons
    elif [ {{ kubernetes_topology }} == "non-ha" ]; then
        just _init-cp-1
        just _join-worker-1
        just _join-worker-2
        just _join-worker-3
        just _copy-kubeconfig cp-1
        just _sign-csrs
        just _install-addons
    elif [ {{ kubernetes_topology }} == "ha" ]; then
        just _init-cp-1
        just _join-cp-2
        just _join-cp-3
        just _join-worker-1
        just _join-worker-2
        just _join-worker-3
        just _copy-kubeconfig cp-1
        just _copy-kubeconfig cp-2
        just _copy-kubeconfig cp-3
        just _sign-csrs
        just _install-addons
    else
        echo 'Non supported Kubernetes cluster topology {{ RED }}<{{ kubernetes_topology }}>{{ NORMAL }}'
    fi

# Perform healthcheck to Kubernetes cluster
[group('kubernetes')]
healthcheck:
    kubectl version
    cilium status
    kubectl get --raw='/readyz?verbose'

[group('kubeadm')]
_init-cp-1:
    scp -F /Users/$USER/.lima/cp-1/ssh.config manifests/kubeadm/out/cp-1-init-config.yaml lima-cp-1:.
    scp -F /Users/$USER/.lima/cp-1/ssh.config manifests/kube-vip/kube-vip.yaml lima-cp-1:.
    ssh -F /Users/$USER/.lima/cp-1/ssh.config lima-cp-1 sudo mv kube-vip.yaml /etc/kubernetes/manifests
    ssh -F /Users/$USER/.lima/cp-1/ssh.config lima-cp-1 "sudo sed -i 's#path: /etc/kubernetes/admin.conf#path: /etc/kubernetes/super-admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml"
    ssh -F /Users/$USER/.lima/cp-1/ssh.config lima-cp-1 sudo kubeadm init --upload-certs --config cp-1-init-config.yaml
    ssh -F /Users/$USER/.lima/cp-1/ssh.config lima-cp-1 "sudo sed -i 's#path: /etc/kubernetes/super-admin.conf#path: /etc/kubernetes/admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml"

[group('kubeadm')]
_join-cp-2:
    scp -F /Users/$USER/.lima/cp-2/ssh.config manifests/kubeadm/out/cp-2-join-config.yaml lima-cp-2:.
    scp -F /Users/$USER/.lima/cp-2/ssh.config manifests/kube-vip/kube-vip.yaml lima-cp-2:.
    ssh -F /Users/$USER/.lima/cp-2/ssh.config lima-cp-2 sudo mv kube-vip.yaml /etc/kubernetes/manifests
    ssh -F /Users/$USER/.lima/cp-2/ssh.config lima-cp-2 sudo kubeadm join --config cp-2-join-config.yaml

[group('kubeadm')]
_join-cp-3:
    scp -F /Users/$USER/.lima/cp-3/ssh.config manifests/kubeadm/out/cp-3-join-config.yaml lima-cp-3:.
    scp -F /Users/$USER/.lima/cp-3/ssh.config manifests/kube-vip/kube-vip.yaml lima-cp-3:.
    ssh -F /Users/$USER/.lima/cp-3/ssh.config lima-cp-3 sudo mv kube-vip.yaml /etc/kubernetes/manifests
    ssh -F /Users/$USER/.lima/cp-3/ssh.config lima-cp-3 sudo kubeadm join --config cp-3-join-config.yaml

[group('kubeadm')]
_join-worker-1:
    scp -F /Users/$USER/.lima/worker-1/ssh.config manifests/kubeadm/out/worker-1-join-config.yaml lima-worker-1:.
    ssh -F /Users/$USER/.lima/worker-1/ssh.config lima-worker-1 sudo kubeadm join --config worker-1-join-config.yaml

[group('kubeadm')]
_join-worker-2:
    scp -F /Users/$USER/.lima/worker-2/ssh.config manifests/kubeadm/out/worker-2-join-config.yaml lima-worker-2:.
    ssh -F /Users/$USER/.lima/worker-2/ssh.config lima-worker-2 sudo kubeadm join --config worker-2-join-config.yaml

[group('kubeadm')]
_join-worker-3:
    scp -F /Users/$USER/.lima/worker-3/ssh.config manifests/kubeadm/out/worker-3-join-config.yaml lima-worker-3:.
    ssh -F /Users/$USER/.lima/worker-3/ssh.config lima-worker-3 sudo kubeadm join --config worker-3-join-config.yaml

[group('kubeadm')]
_copy-kubeconfig node:
    #!/usr/bin/env bash
    set -euxo pipefail
    if [ {{node}} = "cp-1" ]; then
        ssh -F /Users/$USER/.lima/{{node}}/ssh.config lima-{{node}} 'mkdir -p $HOME/.kube'
        ssh -F /Users/$USER/.lima/{{node}}/ssh.config lima-{{node}} 'sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config'
        ssh -F /Users/$USER/.lima/{{node}}/ssh.config lima-{{node}} 'sudo chown $(id -u):$(id -g) $HOME/.kube/config'
        scp -F /Users/$USER/.lima/{{node}}/ssh.config lima-{{node}}:.kube/config ~/.kube/config.k8s-on-macos
        chown $(id -u):$(id -g) ~/.kube/config.k8s-on-macos
        echo "Set kubeconfig envinronment variable on host with 'export KUBECONFIG=~/.kube/config.k8s-on-macos'"
    else
        ssh -F /Users/$USER/.lima/{{node}}/ssh.config lima-{{node}} 'mkdir -p $HOME/.kube'
        ssh -F /Users/$USER/.lima/{{node}}/ssh.config lima-{{node}} 'sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config'
        ssh -F /Users/$USER/.lima/{{node}}/ssh.config lima-{{node}} 'sudo chown $(id -u):$(id -g) $HOME/.kube/config'
    fi

[group('kubeadm')]
_sign-csrs:
    sleep 1
    kubectl get csr | grep "Pending" | awk '{print $1}' | xargs kubectl certificate approve

[group('kubeadm')]
_install-addons:
    kubectl apply --server-side=true -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v{{gatewayapi_version}}/standard-install.yaml
    kubectl apply --server-side=true -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v{{gatewayapi_version}}/experimental-install.yaml
    helm install cilium oci://quay.io/cilium/charts/cilium --version {{cilium_version}} --namespace kube-system --values manifests/cilium/values.yaml
    helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator --namespace flux-system --create-namespace
    cilium status --wait