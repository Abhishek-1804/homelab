cluster := "homelab"

# local tool directory — all deps live here, no system package manager needed
bin := justfile_directory() / "bin"

# put local bin first so every recipe uses these binaries
export PATH := bin + ":" + env_var('PATH')
# keep helm plugins (helm-diff) local to the repo
export HELM_DATA_HOME := bin / ".helm"

# download any missing dependencies into ./bin (no system package manager)
install-deps:
    @hack/install-deps.sh "{{bin}}"

# apply manifests to an existing cluster (kustomize applies image versions)
sync:
    kubectl apply -k manifests/

# pull every image kustomize will deploy into OrbStack's image store, which
# persists across cluster rebuilds. Image list is read from the rendered
# manifests, so it never drifts. Does not need a running cluster.
load-images:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl kustomize manifests/ | yq -N '.. | select(has("image")) | .image' | sort -u | while read -r img; do
        echo "→ $img"
        docker pull "$img"
    done

# inject the pulled images from OrbStack into the kind node's containerd —
# the part `destroy` wipes and would otherwise re-pull from the internet.
kind-load:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl kustomize manifests/ | yq -N '.. | select(has("image")) | .image' | sort -u | while read -r img; do
        echo "→ $img"
        kind load docker-image "$img" --name {{cluster}}
    done

# create cluster and deploy (skips cluster creation if already exists)
deploy: install-deps load-images
    mkdir -p data
    kind get clusters | grep -q '^{{cluster}}$' || \
        DATA_DIR="$(pwd)/data" yq e '.nodes[0].extraMounts = [{"hostPath": strenv(DATA_DIR), "containerPath": "/homelab-data"}]' kind-config.yaml \
        | kind create cluster --name {{cluster}} --config -
    just kind-load
    just sync

# destroy kind cluster
destroy:
    kind delete cluster --name {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy
