cluster := "homelab-kind"

# install all required dependencies (macOS)
[macos]
install-deps:
    brew install kind kubectl helm helmfile
    helm plugin install https://github.com/databus23/helm-diff || true

# check required dependencies (macOS)
[macos]
check-deps:
    @command -v kind     >/dev/null || (echo "missing: kind      → brew install kind"     && exit 1)
    @command -v kubectl  >/dev/null || (echo "missing: kubectl   → brew install kubectl"  && exit 1)
    @command -v helm     >/dev/null || (echo "missing: helm      → brew install helm"     && exit 1)
    @command -v helmfile >/dev/null || (echo "missing: helmfile  → brew install helmfile" && exit 1)
    @echo "all dependencies satisfied"

# trust the homelab CA certificate (macOS) — re-run after rebuild
[macos]
trust-ca:
    @echo "waiting for homelab CA secret..."
    @until kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' 2>/dev/null | grep -q .; do sleep 2; done
    kubectl get secret homelab-ca-secret -n cert-manager \
        -o jsonpath='{.data.tls\.crt}' | base64 -d | \
        sudo security add-trusted-cert -d -r trustRoot \
        -k /Library/Keychains/System.keychain /dev/stdin
    @echo "CA certificate trusted — restart your browser"

# apply manifests to an existing cluster
sync:
    helmfile apply --set controller.admissionWebhooks.enabled=false
    kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=90s
    kubectl apply -f manifests/ingress.yaml
    kubectl apply -f manifests/ -R

# create cluster and deploy (skips cluster creation if already exists)
deploy: check-deps
    kind get clusters | grep -q {{cluster}} || kind create cluster --name {{cluster}} --config kind-cluster.yaml
    just sync
    just trust-ca

# destroy kind cluster
destroy:
    kind delete cluster --name {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy
