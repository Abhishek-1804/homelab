# homelab

A local Kubernetes cluster running on [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker), built as a hands-on environment for learning how Kubernetes actually works.

The goal isn't production readiness — it's to have a real cluster running real services so you can observe and experiment with how things fit together: how a request travels from your browser to a pod, how services discover each other, how storage is provisioned, how TLS is managed automatically, and how declarative configuration translates into running infrastructure.

## What's running

| Service | URL | Purpose |
|---|---|---|
| Homepage | https://homepage.homelab.local | Central dashboard |
| Grafana | https://grafana.homelab.local | Metrics visualization |
| Prometheus | https://prometheus.homelab.local | Metrics collection |
| Uptime Kuma | https://uptime-kuma.homelab.local | Uptime monitoring |
| Open WebUI | https://open-webui.homelab.local | Chat interface for Ollama |
| Ollama | https://ollama.homelab.local | Local LLM inference |
| n8n | https://n8n.homelab.local | Workflow automation |
| Plex | https://plex.homelab.local | Media streaming |
| Jellyfin | https://jellyfin.homelab.local | Media streaming |

## What this teaches

**Networking** — every service is exposed via ingress-nginx, a single nginx controller that routes requests by hostname. Understanding how a browser request reaches a pod means tracing: host DNS → kind NodePort → ingress controller → Kubernetes Service → Pod. There's no magic, just layers.

**Service discovery** — pods don't talk to each other via IPs. Open WebUI reaches Ollama at `http://ollama.ai.svc.cluster.local:80`. This is Kubernetes' internal DNS — every Service gets a stable DNS name regardless of which node its pods land on or how many times they restart.

**TLS** — cert-manager runs a self-signed CA inside the cluster and automatically issues and renews certificates for every service. The CA is trusted on the host machine via the macOS keychain, so all `.homelab.local` domains get valid HTTPS with no manual cert work.

**Storage provisioning** — local-path-provisioner watches for PersistentVolumeClaims and automatically creates directories on the node to back them. This makes the PVC → PV → StorageClass flow concrete: you declare what you need, the provisioner fulfills it, and data survives pod restarts.

**Declarative configuration** — nothing is set up manually inside the cluster. Every resource is a YAML manifest in this repo. Deleting and recreating the entire cluster with `just rebuild` produces the same result every time.

**Namespaces and RBAC** — services are grouped into `ai`, `monitoring`, and `media` namespaces. A ServiceAccount with scoped permissions shows how Kubernetes controls what a pod is allowed to do against the API.

## Prerequisites

```
brew install kind kubectl helm helmfile yq
helm plugin install https://github.com/databus23/helm-diff
```

Or just run:

```
just install-deps
```

## Getting started

```
just deploy
```

This will:
1. Create the kind cluster (3 nodes: 1 control-plane, 2 workers)
2. Install ingress-nginx and cert-manager via Helm
3. Apply all manifests
4. Add all `.homelab.local` hostnames to `/etc/hosts`
5. Trust the homelab CA certificate in the macOS keychain

## Useful commands

```bash
just deploy        # create cluster and deploy everything
just sync          # re-apply manifests to existing cluster
just update-hosts  # sync /etc/hosts with current ingress hostnames
just trust-ca      # re-trust the CA cert (needed after rebuild)
just rebuild       # destroy and recreate from scratch
just destroy       # delete the cluster
```

```bash
kubectl get pods -A                        # see everything running
kubectl get ingress -A                     # see all ingress rules
kubectl get pvc -A                         # see all persistent volume claims
kubectl describe pvc <name> -n <ns>        # see provisioning events
kubectl logs -n ingress-nginx <pod>        # ingress controller logs
```

## Structure

```
homelab/
├── kind-cluster.yaml        # cluster topology (nodes, port mappings)
├── helmfile.yaml            # ingress-nginx and cert-manager helm releases
├── justfile                 # all automation recipes
├── data/                    # persistent volume data (gitignored)
└── manifests/
    ├── ingress.yaml         # namespaces + all ingress rules
    ├── storage.yaml         # local-path-provisioner + StorageClass
    ├── certs/
    │   └── issuer.yaml      # CA + per-namespace TLS certificates
    ├── ai/                  # ollama, open-webui, n8n
    ├── monitoring/          # prometheus, grafana, uptime-kuma, homepage
    └── media/               # plex, jellyfin
```
