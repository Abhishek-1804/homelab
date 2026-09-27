# homelab

A local Kubernetes cluster running on [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker), built as a hands-on environment for learning how Kubernetes actually works.

The goal isn't production readiness — it's to have a real cluster running real services so you can observe and experiment with how things fit together: how a request travels from your browser to a pod, how services discover each other, how storage is provisioned, and how declarative configuration translates into running infrastructure.

## What's running

All services are accessible via NodePort at the host's Tailscale [MagicDNS](https://tailscale.com/kb/1081/magicdns) name (`omarchy-xps.tail53266a.ts.net`), which follows the machine even if its Tailscale IP changes. Homepage is the single entry point — open it and navigate to everything else from there.

| Service | Port | Purpose |
|---|---|---|
| Homepage | [3000](http://omarchy-xps.tail53266a.ts.net:3000) | Central dashboard |
| Grafana | 3001 | Metrics visualization |
| Prometheus | 3002 | Metrics collection |
| Gatus | 3003 | Service health checks |
| Home Assistant | 3004 | Home automation |
| Open WebUI | 3005 | Chat interface for Ollama |
| Ollama | 3006 | Local LLM inference |
| n8n | 3007 | Workflow automation |
| Hermes Agent | 3008 | Autonomous AI agent |
| Plex | 3009 | Media streaming |
| Jellyfin | 3010 | Media streaming |
| Nextcloud | 3011 | File storage |
| Immich | 3012 | Photo and video management |
| IT Tools | 3013 | Developer utilities |
| LibreOffice | 3014 | Online office suite |
| Folding@home | 3015 | Protein-folding research |
| Dozzle | 3016 | Live container logs |

## What this teaches

**Networking** — every service is exposed as a NodePort, a fixed port on the host that maps directly into the cluster. Understanding how a browser request reaches a pod means tracing: host port → kind node → Kubernetes Service → Pod. There's no magic, just layers.

**Service discovery** — pods don't talk to each other via IPs. Open WebUI reaches Ollama at `http://ollama.ai.svc.cluster.local:80`. This is Kubernetes' internal DNS — every Service gets a stable DNS name regardless of which node its pods land on or how many times they restart.

**Storage** — static PersistentVolumes back each service with a fixed hostPath (`/homelab-data/<service>`), which kind bind-mounts from `./data/` on your host. Data survives cluster destruction and recreation because it lives on the host filesystem. The PV → PVC binding flow is explicit: you can see exactly which directory backs which service.

**Declarative configuration** — nothing is set up manually inside the cluster. Every resource is a YAML manifest in this repo. Deleting and recreating the entire cluster with `mise run rebuild` produces the same result every time.

**Namespaces** — services are grouped into `ai`, `monitoring`, `media`, and `it` namespaces.

## Prerequisites

[Docker](https://docs.docker.com/get-docker/) and [mise](https://mise.jdx.dev).
Shell activation (`mise activate`) is optional. The tasks load the pinned tools
themselves, but activation puts `kubectl` and friends on `PATH` for the
commands you type by hand.

Everything else is self-contained, except for the CLI tools. `kind`, `kubectl`,
`helm`, `helmfile`, and `yq` are pinned in `mise.toml`. mise installs
them into its own directory (`~/.local/share/mise`), not into this repo. It
puts them on `PATH` and sets `HELM_DATA_HOME=.helm/` whenever you're inside the
repo. `mise.toml` also holds every automation task: run one with
`mise run <task>` (or `mise r <task>`), and list them with `mise tasks`.
One-time setup:

```
mise trust     # allow mise to load this repo's mise.toml
mise install   # install the pinned tools
```

`mise run deploy` also installs the `helm-diff` plugin (needed by `helmfile apply`)
into `.helm/`.

> To monitor the cluster with [k9s](https://k9scli.io), install it separately
> (e.g. in your global mise config) — this repo doesn't manage it.

## Getting started

```
mise run deploy
```

This will:
1. Install the `helm-diff` plugin and start the local pull-through cache registries
2. Create the kind cluster (single node), with each NodePort mapped to its host
   port per the `extraPortMappings` in `kind-config.yaml`
3. Apply all manifests

Then open **http://omarchy-xps.tail53266a.ts.net:3000** from any device on your Tailscale network.

> If the machine's Tailscale hostname or tailnet changes, update `omarchy-xps.tail53266a.ts.net` in `manifests/monitoring/homepage.yaml`.
>
> If Chrome's **Use secure DNS** is set to a custom provider (e.g. Cloudflare), `.ts.net` names won't resolve in Chrome on this machine — set it to automatic or off at `chrome://settings/security`.

> **Disconnect any VPN (e.g. Surfshark) before deploying.** WireGuard VPNs use
> a smaller MTU (1280) than Docker's bridge (1500), so TLS handshakes from
> containers hang even though the host's own traffic works. The cache
> registries fail to reach their upstreams (`TLS handshake timeout` in
> `docker logs kind-reg-dockerio`) and every pod ends up in `ImagePullBackOff`.
> After disconnecting, delete the stuck pods (or run `mise run rebuild`) so they
> retry.

## Useful commands

```bash
mise tasks                    # list every task
mise run deploy               # create cluster and deploy everything
mise run sync-manifests       # re-apply manifests to existing cluster
mise run rebuild              # destroy and recreate from scratch
mise run destroy              # delete the cluster
mise run clean-data           # delete all service data in data/ (uses sudo)
mise run registry-clean       # stop and remove the cache registries
```

```bash
kubectl get pods -A                        # see everything running
kubectl get svc -A                         # see all services and NodePorts
kubectl get pvc -A                         # see all persistent volume claims
kubectl describe pvc <name> -n <ns>        # see PV binding details
kubectl logs -n <namespace> <pod>          # pod logs
kubectl exec -it -n <namespace> <pod> -- bash  # shell into a pod
```

## Adding a service

Nothing is auto-discovered — each new service is wired in by hand across a few
files. Pick the next free port number `N` (NodePort `3000N`, host port `300N`)
and touch these files:

1. **`manifests/<namespace>/<service>.yaml`** — the workload. A `Deployment`, a
   NodePort `Service` (`nodePort: 3000N`), and a `PersistentVolumeClaim` if it
   needs storage. Copy `manifests/science/foldingathome.yaml` as a template.

2. **`manifests/volumes.yaml`** — if the service needs storage, add a static
   `PersistentVolume` with `hostPath: /homelab-data/<service>` matching the PVC's
   `volumeName`.

3. **`manifests/namespaces.yaml`** — only if the service lives in a new namespace.

4. **`manifests/kustomization.yaml`** — add the manifest path to `resources:`,
   and add the container image to `images:` so its version is pinned centrally.

5. **`kind-config.yaml`** — add an `extraPortMappings` entry mapping
   `containerPort: 3000N` → `hostPort: 300N`. If the image comes from a new
   registry domain, also add a mirror under `containerdConfigPatches` (and a
   matching cache container in `hack/registry.sh`).

6. **`manifests/monitoring/homepage.yaml`** — add the service to the dashboard.

7. **`manifests/monitoring/gatus.yaml`** — add a health-check endpoint using the
   service's in-cluster DNS name.

8. **`README.md`** — add a row to the service table above.

Then apply:

```bash
mise run sync-manifests  # if you only changed manifests
mise run rebuild         # if you changed kind-config.yaml — port mappings and
                         # registry mirrors only take effect when the cluster is created
```

> The most common gotcha: edits to `kind-config.yaml` do **nothing** on a running
> cluster. Port mappings and registry mirrors are baked in at cluster-creation
> time, so a new host port or registry requires `mise run rebuild`, not `mise run sync-manifests`.

## Structure

```
homelab/
├── kind-config.yaml         # cluster topology (node, ports, data mount)
├── helmfile.yaml            # helm releases (currently unused)
├── mise.toml                # pinned CLI tools and all automation tasks
├── hack/registry.sh         # pull-through cache registries
├── data/                    # persistent volume data (gitignored)
└── manifests/
    ├── namespaces.yaml      # namespace definitions
    ├── volumes.yaml         # static PersistentVolumes backed by ./data/
    ├── ai/                  # ollama, open-webui, n8n, hermes-agent
    ├── monitoring/          # prometheus, grafana, gatus, homepage, home-assistant, dozzle
    ├── media/               # plex, jellyfin, nextcloud, immich
    └── it/                  # it-tools, libreoffice
```
