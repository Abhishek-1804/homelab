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

# start the local pull-through cache registries (cache survives rebuilds)
registry:
    @hack/registry.sh

# stop and remove the cache registries (cached layers in their volumes stay)
registry-clean:
    -docker rm -f kind-reg-dockerio kind-reg-ghcr kind-reg-lscr kind-reg-n8n

# create cluster and deploy (skips cluster creation if already exists)
deploy: install-deps registry
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
