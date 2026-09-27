cluster := "homelab"

# tools (kind, kubectl, helm, ...) and HELM_DATA_HOME come from mise.toml

# install the helm-diff plugin (required by `helmfile apply`) into .helm/
helm-plugins:
    @helm plugin list | grep -q '^diff' || helm plugin install https://github.com/databus23/helm-diff --version v3.9.13

# apply manifests to an existing cluster (kustomize applies image versions)
sync-manifests:
    kubectl apply -k manifests/

# start the local pull-through cache registries (cache survives rebuilds)
registry:
    @hack/registry.sh

# stop and remove the cache registries (cached layers in their volumes stay)
registry-clean:
    -docker rm -f kind-reg-dockerio kind-reg-ghcr kind-reg-lscr kind-reg-n8n

# create cluster and deploy (skips cluster creation if already exists)
deploy: helm-plugins registry
    mkdir -p data
    kind get clusters | grep -q '^{{cluster}}$' || \
        DATA_DIR="$(pwd)/data" yq e '.nodes[0].extraMounts = [{"hostPath": strenv(DATA_DIR), "containerPath": "/homelab-data"}]' kind-config.yaml \
        | kind create cluster --name {{cluster}} --config -
    just sync-manifests

# destroy kind cluster
destroy:
    kind delete cluster --name {{cluster}}

# destroy and recreate cluster from scratch
rebuild: destroy deploy

# delete all service data (files are owned by container users, hence sudo)
clean-data:
    sudo rm -rf data/

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
