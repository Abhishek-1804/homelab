# homelab

A k3s cluster on a headless server, hosting the Hermes agent. Everything is
managed with [mise](https://mise.jdx.dev) from the laptop.

| File | What it is |
|---|---|
| `mise.toml` | Laptop: tools, the server inventory, tasks |
| `mise.server.toml` | Everything on a server: packages, SSH, firewall, k3s |
| `manifests/` | What runs in the cluster |

## Servers

Servers are listed in `mise.toml`. To add one, add a block:

```toml
[bootstrap.remote.hosts.homelab-2]
host     = "homelab-2"      # its Tailscale name
mise_env = ["server"]
```

## Setting up a server

On the fresh server (Omarchy), once, at its own keyboard:
`sudo systemctl enable --now sshd`, then copy your SSH key to it.

From the laptop:

```bash
mise run setup homelab-1 abhishek@192.168.1.50   # first run, over the LAN; prints a Tailscale login URL
mise run up                                       # over Tailscale; turns the firewall on
mise run deploy                                   # secrets + apps
```

`setup` installs the packages, sets SSH to keys only, keeps the laptop awake
with the lid closed, logs in to Tailscale and installs k3s. `up` repeats all of
that over Tailscale and adds the firewall. After that, **the server is
reachable only over Tailscale.** Run `mise run up` any time to re-apply.

| Task | Does |
|---|---|
| `mise run ping` | Every server: up or down, over Tailscale and SSH |
| `mise run kubeconfig` | Lets `kubectl`/`k9s` on the laptop reach the cluster |

## Secrets

Hermes' secrets live in a **1Password Environment**. The desktop app mounts it
as a file at `.secrets/hermes.env`, which is gitignored and never sent to the
servers. `mise run deploy` turns it into the `hermes-env` Kubernetes Secret, and
each line becomes an env var in the Hermes pod.

To set it up in 1Password: open **Developer → Environments**, create an
environment, and add the variables (e.g. `CLAUDE_CODE_OAUTH_TOKEN`). Then add
the destination **Local .env file** with the path `.secrets/hermes.env` in this
repo.

To change a secret, edit it in 1Password and run `mise run deploy`.

## Services

| Service | URL |
|---|---|
| Homepage | http://homelab-1.tail53266a.ts.net:30000 |
| Gatus | :30003 |
| Hermes Agent | :30008 |
| Dozzle | :30016 |

## Good to know

- **Disk encryption:** Omarchy encrypts the disk, so after a reboot the server
  waits for the passphrase at its own keyboard.
- **No backups:** data under `/srv/homelab` on the server is **not backed up**,
  so keep the `hermes-backups` repo for now.
