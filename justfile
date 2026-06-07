cluster := "homelab"

# install all required dependencies
[macos]
install-deps:
    brew install kind kubectl yq

[linux]
install-deps:
    curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 \
        && chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind
    curl -Lo /tmp/kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
        && chmod +x /tmp/kubectl && sudo mv /tmp/kubectl /usr/local/bin/kubectl
    curl -Lo /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
        && chmod +x /tmp/yq && sudo mv /tmp/yq /usr/local/bin/yq

# check required dependencies
[macos]
check-deps:
    @command -v kind    >/dev/null || (echo "missing: kind    → brew install kind"    && exit 1)
    @command -v kubectl >/dev/null || (echo "missing: kubectl → brew install kubectl" && exit 1)
    @command -v yq      >/dev/null || (echo "missing: yq      → brew install yq"      && exit 1)
    @echo "all dependencies satisfied"

[linux]
check-deps:
    @command -v kind    >/dev/null || (echo "missing: kind    → https://kind.sigs.k8s.io/docs/user/quick-start/#installation" && exit 1)
    @command -v kubectl >/dev/null || (echo "missing: kubectl → https://dl.k8s.io/release/stable.txt"                         && exit 1)
    @command -v yq      >/dev/null || (echo "missing: yq      → https://github.com/mikefarah/yq/releases"                     && exit 1)
    @echo "all dependencies satisfied"

# apply manifests to an existing cluster
sync:
    kubectl apply -f manifests/namespaces.yaml
    kubectl apply -f manifests/ -R

# create cluster and deploy (skips cluster creation if already exists)
deploy: check-deps
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p data
    if ! kind get clusters | grep -q '^{{cluster}}$'; then
        DATA_DIR="$(pwd)/data"
        TMPCONFIG=$(mktemp --suffix=.yaml)
        trap "rm -f $TMPCONFIG" EXIT

        # Inject extraMounts
        DATA_DIR="$DATA_DIR" yq e \
            '.nodes[0].extraMounts = [{"hostPath": strenv(DATA_DIR), "containerPath": "/homelab-data"}]' \
            kind-config.yaml > "$TMPCONFIG"

        # Auto-generate extraPortMappings from all NodePort services in manifests/
        PORTS=$(find manifests -name "*.yaml" \
            | xargs yq ea 'select(.kind == "Service") | .spec.ports[] | select(.nodePort != null) | .nodePort' 2>/dev/null \
            | sort -u \
            | awk '{print "{\"containerPort\":" $1 ",\"hostPort\":" $1 "}"}' \
            | paste -sd ',')

        if [ -n "$PORTS" ]; then
            yq e ".nodes[0].extraPortMappings = [$PORTS]" -i "$TMPCONFIG"
        fi

        kind create cluster --name {{cluster}} --config "$TMPCONFIG"
    fi
    just sync

# destroy kind cluster
destroy:
    kind delete cluster --name {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy
