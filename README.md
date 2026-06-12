# homelab

A local Kubernetes cluster running on [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker), built as a hands-on environment for learning how Kubernetes actually works.

The goal isn't production readiness — it's to have a real cluster running real services so you can observe and experiment with how things fit together: how a request travels from your browser to a pod, how services discover each other, how storage is provisioned, and how declarative configuration translates into running infrastructure.

## What's running

All services are accessible via NodePort at the host's Tailscale IP (`100.122.254.107`). Homepage is the single entry point — open it and navigate to everything else from there.

| Service | Port | Purpose |
|---|---|---|
| Homepage | [3000](http://100.122.254.107:3000) | Central dashboard |
| Grafana | 3001 | Metrics visualization |
| Prometheus | 3002 | Metrics collection |
| Uptime Kuma | 3003 | Uptime monitoring |
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

## What this teaches

**Networking** — every service is exposed as a NodePort, a fixed port on the host that maps directly into the cluster. Understanding how a browser request reaches a pod means tracing: host port → kind node → Kubernetes Service → Pod. There's no magic, just layers.

**Service discovery** — pods don't talk to each other via IPs. Open WebUI reaches Ollama at `http://ollama.ai.svc.cluster.local:80`. This is Kubernetes' internal DNS — every Service gets a stable DNS name regardless of which node its pods land on or how many times they restart.

**Storage** — static PersistentVolumes back each service with a fixed hostPath (`/homelab-data/<service>`), which kind bind-mounts from `./data/` on your host. Data survives cluster destruction and recreation because it lives on the host filesystem. The PV → PVC binding flow is explicit: you can see exactly which directory backs which service.

**Declarative configuration** — nothing is set up manually inside the cluster. Every resource is a YAML manifest in this repo. Deleting and recreating the entire cluster with `just rebuild` produces the same result every time.

**Namespaces** — services are grouped into `ai`, `monitoring`, `media`, and `it` namespaces.

## Prerequisites

Downloads pinned `kind`, `kubectl`, `helm`, `helmfile`, and `yq` binaries
(plus the `helm-diff` plugin) into a local `bin/` — no system package manager
required, works on macOS and Linux (amd64/arm64):

```
just install-deps
```

All other recipes use these local binaries (`bin/` is first on `PATH`).

> To monitor the cluster with [k9s](https://k9scli.io), install it separately —
> it is not managed by `just install-deps`.

## Getting started

```
just deploy
```

This will:
1. Create the kind cluster (single node)
2. Auto-map all NodePort services to host ports
3. Apply all manifests

Then open **http://100.122.254.107:3000** from any device on your Tailscale network.

> If you change the Tailscale IP, update `100.122.254.107` in `justfile` and `manifests/monitoring/homepage.yaml`.

## Useful commands

```bash
just deploy    # create cluster and deploy everything
just sync      # re-apply manifests to existing cluster
just rebuild   # destroy and recreate from scratch
just destroy   # delete the cluster
```

```bash
kubectl get pods -A                        # see everything running
kubectl get svc -A                         # see all services and NodePorts
kubectl get pvc -A                         # see all persistent volume claims
kubectl describe pvc <name> -n <ns>        # see PV binding details
kubectl logs -n <namespace> <pod>          # pod logs
kubectl exec -it -n <namespace> <pod> -- bash  # shell into a pod
```

## Structure

```
homelab/
├── kind-config.yaml         # cluster topology (node, ports, data mount)
├── helmfile.yaml            # helm releases (currently unused)
├── justfile                 # all automation recipes
├── data/                    # persistent volume data (gitignored)
└── manifests/
    ├── namespaces.yaml      # namespace definitions
    ├── volumes.yaml         # static PersistentVolumes backed by ./data/
    ├── ai/                  # ollama, open-webui, n8n, hermes-agent
    ├── monitoring/          # prometheus, grafana, uptime-kuma, homepage, home-assistant
    ├── media/               # plex, jellyfin, nextcloud, immich
    └── it/                  # it-tools, libreoffice
```
