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
| Home Assistant | https://home-assistant.homelab.local | Home automation |
| Open WebUI | https://open-webui.homelab.local | Chat interface for Ollama |
| Ollama | https://ollama.homelab.local | Local LLM inference |
| n8n | https://n8n.homelab.local | Workflow automation |
| Plex | https://plex.homelab.local | Media streaming |
| Jellyfin | https://jellyfin.homelab.local | Media streaming |
| Nextcloud | https://nextcloud.homelab.local | File storage |
| Immich | https://immich.homelab.local | Photo and video management |
| IT Tools | https://it-tools.homelab.local | Developer utilities |
| LibreOffice | https://libreoffice.homelab.local | Online office suite |

## What this teaches

**Networking** — every service is exposed via ingress-nginx, a single nginx controller that routes requests by hostname. Understanding how a browser request reaches a pod means tracing: host DNS → kind NodePort → ingress controller → Kubernetes Service → Pod. There's no magic, just layers.

**Service discovery** — pods don't talk to each other via IPs. Open WebUI reaches Ollama at `http://ollama.ai.svc.cluster.local:80`. This is Kubernetes' internal DNS — every Service gets a stable DNS name regardless of which node its pods land on or how many times they restart.

**TLS** — cert-manager runs a self-signed CA inside the cluster and automatically issues and renews certificates for every service. The CA is trusted on the host machine via the macOS keychain, so all `.homelab.local` domains get valid HTTPS with no manual cert work.

**Storage** — static PersistentVolumes back each service with a fixed hostPath (`/homelab-data/<service>`), which kind bind-mounts from `./data/` on your Mac. Data survives cluster destruction and recreation because it lives on the host filesystem. The PV → PVC binding flow is explicit: you can see exactly which directory backs which service.

**Declarative configuration** — nothing is set up manually inside the cluster. Every resource is a YAML manifest in this repo. Deleting and recreating the entire cluster with `just rebuild` produces the same result every time.

**Namespaces and RBAC** — services are grouped into `ai`, `monitoring`, `media`, and `it` namespaces. A ServiceAccount with scoped permissions shows how Kubernetes controls what a pod is allowed to do against the API.

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
1. Create the kind cluster (single node)
2. Install ingress-nginx and cert-manager via Helm
3. Apply all manifests
4. Add all `.homelab.local` hostnames to `/etc/hosts`
5. Trust the homelab CA certificate in the macOS keychain

## Accessing from another machine on your Tailscale network

The ingress controller is already exposed on ports 80 and 443 of the host, so any machine on your Tailscale network can reach it. You just need to point the `.homelab.local` hostnames at the host's Tailscale IP and trust the homelab CA cert.

**Step 1 — Get the Tailscale IP of the homelab host**

Run on the homelab host:

```bash
tailscale ip -4
```

**Step 2 — Add `/etc/hosts` entries on the remote machine**

On macOS, run (replace `<tailscale-ip>`):

```bash
sudo sed -i '' '/\.homelab\.local/d' /etc/hosts && \
sudo sh -c 'echo "<tailscale-ip> homepage.homelab.local grafana.homelab.local prometheus.homelab.local uptime-kuma.homelab.local home-assistant.homelab.local open-webui.homelab.local n8n.homelab.local ollama.homelab.local it-tools.homelab.local libreoffice.homelab.local nextcloud.homelab.local plex.homelab.local jellyfin.homelab.local immich.homelab.local" >> /etc/hosts'
```

**Step 3 — Trust the homelab CA cert on the remote machine**

On macOS, run (replace `<user>` and `<tailscale-ip>`):

```bash
ssh <user>@<tailscale-ip> \
  "kubectl get secret homelab-ca-secret -n cert-manager \
   -o jsonpath='{.data.tls\.crt}' | base64 -d" > /tmp/homelab-ca.crt

sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/homelab-ca.crt
```

Restart your browser after trusting the cert.

**Step 4 — Open the dashboard**

```
https://homepage.homelab.local
```

> If you rebuild the cluster (`just rebuild`), repeat step 3 — a new CA cert is generated each time.

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
kubectl describe pvc <name> -n <ns>        # see PV binding details
kubectl logs -n ingress-nginx <pod>        # ingress controller logs
```

## Structure

```
homelab/
├── kind-config.yaml         # cluster topology (node, port mappings, data mount)
├── helmfile.yaml            # ingress-nginx and cert-manager helm releases
├── justfile                 # all automation recipes
├── data/                    # persistent volume data (gitignored)
└── manifests/
    ├── ingress.yaml         # namespaces + all ingress rules
    ├── volumes.yaml         # static PersistentVolumes backed by ./data/
    ├── certs/
    │   └── issuer.yaml      # CA + per-namespace TLS certificates
    ├── ai/                  # ollama, open-webui, n8n
    ├── monitoring/          # prometheus, grafana, uptime-kuma, homepage, home-assistant
    ├── media/               # plex, jellyfin, nextcloud, immich
    └── it/                  # it-tools, libreoffice
```
