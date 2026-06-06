cluster := "homelab"

# install all required dependencies
[macos]
install-deps:
    brew install kind kubectl helm helmfile yq
    helm plugin install https://github.com/databus23/helm-diff || true

[linux]
install-deps:
    curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 \
        && chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind
    curl -Lo /tmp/kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
        && chmod +x /tmp/kubectl && sudo mv /tmp/kubectl /usr/local/bin/kubectl
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    HELMFILE_VER=$(curl -s https://api.github.com/repos/helmfile/helmfile/releases/latest | grep '"tag_name"' | cut -d'"' -f4) \
        && curl -Lo /tmp/helmfile.tar.gz "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VER}/helmfile_${HELMFILE_VER#v}_linux_amd64.tar.gz" \
        && tar -xzf /tmp/helmfile.tar.gz -C /tmp helmfile \
        && sudo mv /tmp/helmfile /usr/local/bin/helmfile
    curl -Lo /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
        && chmod +x /tmp/yq && sudo mv /tmp/yq /usr/local/bin/yq
    helm plugin install https://github.com/databus23/helm-diff || true

# check required dependencies
[macos]
check-deps:
    @command -v kind     >/dev/null || (echo "missing: kind      → brew install kind"     && exit 1)
    @command -v kubectl  >/dev/null || (echo "missing: kubectl   → brew install kubectl"  && exit 1)
    @command -v helm     >/dev/null || (echo "missing: helm      → brew install helm"     && exit 1)
    @command -v helmfile >/dev/null || (echo "missing: helmfile  → brew install helmfile" && exit 1)
    @command -v yq       >/dev/null || (echo "missing: yq        → brew install yq"       && exit 1)
    @echo "all dependencies satisfied"

[linux]
check-deps:
    @command -v kind     >/dev/null || (echo "missing: kind      → https://kind.sigs.k8s.io/docs/user/quick-start/#installation" && exit 1)
    @command -v kubectl  >/dev/null || (echo "missing: kubectl   → https://dl.k8s.io/release/stable.txt"                          && exit 1)
    @command -v helm     >/dev/null || (echo "missing: helm      → https://helm.sh/docs/intro/install/"                          && exit 1)
    @command -v helmfile >/dev/null || (echo "missing: helmfile  → https://github.com/helmfile/helmfile/releases"                && exit 1)
    @command -v yq       >/dev/null || (echo "missing: yq        → https://github.com/mikefarah/yq/releases"                      && exit 1)
    @echo "all dependencies satisfied"

# sync /etc/hosts with hostnames defined in ingress.yaml
[macos]
update-hosts:
    @sudo -v
    @echo "updating /etc/hosts..."
    @sudo sed -i '' '/\.homelab\.local/d' /etc/hosts
    @yq eval 'select(.kind == "Ingress") | .spec.rules[].host' manifests/ingress.yaml \
        | xargs -I{} sudo sh -c 'echo "127.0.0.1 {}" >> /etc/hosts'
    @echo "done — current homelab entries:"
    @grep homelab /etc/hosts

[linux]
update-hosts:
    @sudo -v
    @echo "updating /etc/hosts..."
    @sudo sed -i '/\.homelab\.local/d' /etc/hosts
    @yq eval 'select(.kind == "Ingress") | .spec.rules[].host' manifests/ingress.yaml \
        | xargs -I{} sudo sh -c 'echo "127.0.0.1 {}" >> /etc/hosts'
    @echo "done — current homelab entries:"
    @grep homelab /etc/hosts

# trust the homelab CA certificate — re-run after rebuild
[macos]
trust-ca:
    @sudo -v
    @echo "waiting for homelab CA secret..."
    @until kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' 2>/dev/null | grep -q .; do sleep 2; done
    kubectl get secret homelab-ca-secret -n cert-manager \
        -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/homelab-ca.crt
    sudo security add-trusted-cert -d -r trustRoot \
        -k /Library/Keychains/System.keychain /tmp/homelab-ca.crt
    rm /tmp/homelab-ca.crt
    @echo "CA certificate trusted — restart your browser"

[linux]
trust-ca:
    @sudo -v
    @echo "waiting for homelab CA secret..."
    @until kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' 2>/dev/null | grep -q .; do sleep 2; done
    kubectl get secret homelab-ca-secret -n cert-manager \
        -o jsonpath='{.data.tls\.crt}' | base64 -d \
        | sudo tee /usr/local/share/ca-certificates/homelab-ca.crt > /dev/null
    sudo update-ca-certificates
    @echo "CA certificate trusted — restart your browser"

# apply manifests to an existing cluster
sync:
    helmfile apply
    kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=120s
    kubectl apply -f manifests/ingress.yaml
    kubectl apply -f manifests/ -R

# create cluster and deploy (skips cluster creation if already exists)
deploy: check-deps
    mkdir -p data
    kind get clusters | grep -q '^{{cluster}}$' || \
        DATA_DIR="$(pwd)/data" yq e '.nodes[0].extraMounts = [{"hostPath": strenv(DATA_DIR), "containerPath": "/homelab-data"}]' kind-config.yaml \
        | kind create cluster --name {{cluster}} --config -
    just sync
    just update-hosts
    just trust-ca

# destroy kind cluster
destroy:
    kind delete cluster --name {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy
