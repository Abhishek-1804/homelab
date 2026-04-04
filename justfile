cluster := "homelab-kind"

# install all required dependencies
[macos]
install-deps:
    brew install kind kubectl helm helmfile yq
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

# apply manifests to an existing cluster
sync:
    helmfile apply --set controller.admissionWebhooks.enabled=false
    kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=90s
    kubectl apply -f manifests/ingress.yaml
    kubectl apply -f manifests/ -R

# create cluster and deploy (skips cluster creation if already exists)
deploy: check-deps
    mkdir -p data
    kind get clusters | grep -q {{cluster}} || \
        DATA_DIR="$(pwd)/data" yq e '.nodes[].extraMounts = [{"hostPath": strenv(DATA_DIR), "containerPath": "/homelab-data"}]' kind-cluster.yaml \
        | kind create cluster --name {{cluster}} --config -
    just sync
    just update-hosts
    just trust-ca

# destroy kind cluster
destroy:
    kind delete cluster --name {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy
