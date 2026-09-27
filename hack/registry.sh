#!/usr/bin/env bash
# Pull-through cache registries: cluster rebuilds load images from a local
# cache instead of re-pulling from the internet. One proxy per upstream; the
# cache lives in a named docker volume (survives rebuilds). Run by `mise run deploy`.
set -euo pipefail

NET=kind  # kind attaches nodes to a docker network named "kind"
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null

# name|upstream — name is the container, the named volume, and the host that
# kind-config.yaml mirrors to. Add a line when manifests use a new registry.
for r in \
  "kind-reg-dockerio|https://registry-1.docker.io" \
  "kind-reg-ghcr|https://ghcr.io" \
  "kind-reg-lscr|https://lscr.io" \
  "kind-reg-n8n|https://docker.n8n.io"; do
    name=${r%%|*}; upstream=${r##*|}
    if [ -z "$(docker ps -q -f "name=^${name}$")" ]; then
        echo "→ $name → $upstream"
        docker rm -f "$name" >/dev/null 2>&1 || true   # recreate if stopped; volume persists
        # registry:2 panics if the upstream is unreachable at startup (e.g.
        # a network blip); restart so it recovers instead of staying dead.
        docker run -d --name "$name" --restart unless-stopped \
            -e REGISTRY_PROXY_REMOTEURL="$upstream" \
            -v "$name:/var/lib/registry" \
            registry:2 >/dev/null
    fi
    docker network connect "$NET" "$name" 2>/dev/null || true
done
echo "pull-through registries ready"
