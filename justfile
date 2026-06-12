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

# apply manifests to an existing cluster
sync:
    kubectl apply -f manifests/namespaces.yaml
    kubectl apply -f manifests/ -R

# create cluster and deploy (skips cluster creation if already exists)
deploy: install-deps
    mkdir -p data
    kind get clusters | grep -q '^{{cluster}}$' || \
        DATA_DIR="$(pwd)/data" yq e '.nodes[0].extraMounts = [{"hostPath": strenv(DATA_DIR), "containerPath": "/homelab-data"}]' kind-config.yaml \
        | kind create cluster --name {{cluster}} --config -
    just sync

# destroy kind cluster
destroy:
    kind delete cluster --name {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy
