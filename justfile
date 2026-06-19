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

# --- global docker cleanup (affects ALL docker, not just homelab) ---

# stop and remove every container
docker-clean-containers:
    #!/usr/bin/env bash
    ids=$(docker ps -aq); [ -n "$ids" ] && docker rm -f $ids || echo "no containers"

# remove every image (clears containers first — they hold image references)
docker-clean-images: docker-clean-containers
    #!/usr/bin/env bash
    ids=$(docker images -aq); [ -n "$ids" ] && docker rmi -f $ids || echo "no images"

# remove every volume (clears containers first — running ones hold volumes)
docker-clean-volumes: docker-clean-containers
    #!/usr/bin/env bash
    ids=$(docker volume ls -q); [ -n "$ids" ] && docker volume rm -f $ids || echo "no volumes"

# remove every user-defined network (clears containers first; built-ins kept)
docker-clean-networks: docker-clean-containers
    #!/usr/bin/env bash
    ids=$(docker network ls --filter type=custom -q); [ -n "$ids" ] && docker network rm $ids || echo "no networks"

# wipe ALL docker state: containers, images, volumes, networks
docker-nuke: docker-clean-images docker-clean-volumes docker-clean-networks
