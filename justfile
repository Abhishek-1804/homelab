cluster := "homelab"

# install all required dependencies
[macos]
install-deps:
    brew install minikube kubectl helm helmfile yq vfkit
    helm plugin install https://github.com/databus23/helm-diff || true

# check required dependencies
[macos]
check-deps:
    @command -v minikube  >/dev/null || (echo "missing: minikube  → brew install minikube"  && exit 1)
    @command -v kubectl   >/dev/null || (echo "missing: kubectl   → brew install kubectl"   && exit 1)
    @command -v helm      >/dev/null || (echo "missing: helm      → brew install helm"      && exit 1)
    @command -v helmfile  >/dev/null || (echo "missing: helmfile  → brew install helmfile"  && exit 1)
    @command -v yq        >/dev/null || (echo "missing: yq        → brew install yq"        && exit 1)
    @echo "all dependencies satisfied"

# configure macOS to resolve *.homelab.local via minikube's ingress-dns addon
# vfkit gives the VM a real routable IP so this works without any /etc/hosts hacks
[macos]
setup-dns:
    @sudo mkdir -p /etc/resolver
    @minikube ip --profile {{cluster}} | xargs -I{} sudo sh -c 'echo "nameserver {}" > /etc/resolver/homelab.local'
    @echo "DNS configured — *.homelab.local resolves via $$(minikube ip --profile {{cluster}})"

# trust the homelab CA certificate — re-run after rebuild
[macos]
trust-ca:
    @echo "waiting for homelab CA secret..."
    @until kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' 2>/dev/null | grep -q .; do sleep 2; done
    kubectl get secret homelab-ca-secret -n cert-manager \
        -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/homelab-ca.crt
    sudo security add-trusted-cert -d -r trustRoot \
        -k /Library/Keychains/System.keychain /tmp/homelab-ca.crt
    rm /tmp/homelab-ca.crt
    @echo "CA certificate trusted — restart your browser"

# apply manifests to an existing cluster
sync:
    helmfile apply
    kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=120s
    kubectl apply -f manifests/ingress.yaml
    kubectl apply -f manifests/ -R

# create cluster and deploy (skips cluster creation if already exists)
deploy: check-deps
    @sudo -v
    mkdir -p data
    minikube status --profile {{cluster}} | grep -q Running || \
        minikube start \
            --profile {{cluster}} \
            --mount \
            --mount-string="$(pwd)/data:/homelab-data" \
            --addons=ingress \
            --addons=ingress-dns \
            --driver=vfkit
    just sync
    just setup-dns
    just trust-ca

# destroy minikube cluster
destroy:
    minikube delete --profile {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy
