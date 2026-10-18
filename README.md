# homelab

A k3s cluster on a headless server, hosting the Hermes agent. Everything is
managed with [mise](https://mise.jdx.dev) from the laptop.

| File | What it is |
|---|---|
| `mise.toml` | Laptop: tools, the server inventory, tasks |
| `mise.server.toml` | Everything on a server: packages, SSH, firewall, k3s |
| `manifests/` | What runs in the cluster |
| `tf/` | Throwaway EC2 servers for testing the setup flow |

## Requirements

### Accounts

| Account | Used for |
|---|---|
| GitHub | This repo; servers import your SSH key from it |
| Tailscale | The private network you reach the servers through |
| 1Password | Every secret (the `homelab` Environment) |
| AWS | Test servers in `tf/` only, through `aws login` (no stored keys) |

### On the laptop

Install these yourself:

| Tool | Why |
|---|---|
| [mise](https://mise.jdx.dev) | Runs every task and installs the tools below |
| Tailscale | Reaches the servers after setup |
| An SSH key, also added to GitHub | Logging in to the servers. Kept in 1Password: Settings → Developer → **Use the SSH agent**, and `IdentityAgent ~/.1password/agent.sock` in `~/.ssh/config` |
| 1Password desktop app | Mounts the secrets as `.env` (Developer → Environments) and holds the SSH key |
| AWS CLI | Signs in to AWS before using `tf/` |

mise installs the rest at the versions pinned in `mise.toml`: `kubectl` and
`terraform` with `mise install`, and `yq` the first time `mise run ping` runs.

### Before running tasks

| Check | Needed for | How |
|---|---|---|
| Your SSH key is on GitHub | Every server: they authorize the keys at `github.com/<github-user>.keys` | GitHub → Settings → SSH keys. `tf/vars.tf` sets `github_user` |
| Tailscale is connected | `up`, `ping`, `kubeconfig`, `deploy` | `tailscale status` |
| 1Password is unlocked | `deploy` (it reads `.env`) | Open the desktop app |
| Signed in to AWS | `tf-plan`, `tf-apply`, `tf-destroy` | `mise run tf-login`; check with `aws sts get-caller-identity` |

### On a server

The only manual step is installing **Ubuntu Server** (24.04 or 26.04 LTS) with
two things working:

- **Wi-Fi:** connected, so the server has a LAN IP and internet.
- **SSH:** `openssh-server` running, with your key authorized
  (`ssh-import-id gh:<github-user>`), so `ssh <user>@<lan-ip>` works without a password.

Everything else is code. `mise.server.toml` installs `openssh-server`,
`tailscale`, `ufw` and `unattended-upgrades`, and then k3s at the version
pinned in `mise.toml`.

## Setting up a server

From the laptop:

```bash
mise run setup homelab-1 abhishek@192.168.1.50   # first run, over the LAN; prints a Tailscale login URL
mise run up                                       # over Tailscale; turns the firewall on
mise run deploy                                   # secrets + apps
```

`setup` sets the hostname, installs the packages, sets SSH to keys only, keeps
the laptop awake with the lid closed, logs in to Tailscale and installs k3s.
`up` repeats all of that over Tailscale and adds the firewall. After that,
**the server is reachable only over Tailscale.** Run `mise run up` any time to
re-apply.

| Task | Does |
|---|---|
| `mise run ping` | Every server: up or down, over Tailscale and SSH |
| `mise run kubeconfig` | Lets `kubectl`/`k9s` on the laptop reach the cluster |

To add a server, add a block to `mise.toml`:

```toml
[bootstrap.remote.hosts.homelab-2]
host     = "homelab-2"      # its Tailscale name
mise_env = ["server"]
```

## Secrets

All secrets live in one **1Password Environment**, `homelab`. The desktop app
mounts it as `.env` in this repo, which is gitignored and never sent to the
servers. `mise run deploy` loads it into the `homelab-env` Kubernetes Secret,
which k3s stores encrypted. Hermes gets each line as an env var.

**Any pod given this Secret sees every value in it**, so only put in secrets
its users may all see. Today that's just Hermes. That's also why AWS access
doesn't go here (see below).

To set it up in 1Password: open **Developer → Environments**, create `homelab`,
and add the variables (e.g. `CLAUDE_CODE_OAUTH_TOKEN`). Then add the
destination **Local .env file** with the path `.env` in this repo.

| Task | Does |
|---|---|
| `mise run deploy` | Pushes the current secrets to the cluster (after any change in 1Password) |
| `mise run env-local` | Writes `.env.local`: the variable names in `.env`, without values |

## Test servers on AWS (`tf/`)

`tf/` creates throwaway EC2 instances to try the setup flow on a fresh machine.
Later it will be used for CI as well.

**Logging in** uses `aws login`: you sign in through the browser as an IAM
user and the CLI gets short-lived credentials. No AWS keys are stored
anywhere, and the root user is kept for billing only. Set it up once:

1. As root, in **IAM** → **Users**, create `akdp` with console access and the
   `PowerUserAccess` policy (everything except IAM). Sign in as it with
   your account ID and add MFA.
2. `mise run tf-login` and sign in as `akdp`. That saves the `homelab`
   profile in `~/.aws/config` (`mise.toml` sets `AWS_PROFILE=homelab` for
   this repo).

Then, each session:

| Task | Does |
|---|---|
| `mise run tf-login` | Signs in to AWS (`aws login`) when the credentials expire |
| `mise run tf-init` | Downloads the providers (once) |
| `mise run tf-plan` | Shows what would be created |
| `mise run tf-apply` | Creates a `t3.small` Ubuntu 26.04 server (about $0.025/hour) and prints `ssh ubuntu@<ip>` |
| `mise run tf-destroy` | **When done:** deletes everything `tf/` created |

The server lets in your GitHub SSH keys (key import can take a minute after
boot). Settings such as the instance type are in `tf/vars.tf`.

**Terraform state** is `tf/terraform.tfstate` on the laptop (gitignored). It is
the only record of what exists in AWS, so run `mise run tf-destroy` before you
ever delete it. Test servers that logged in to Tailscale also need removing
from the Tailscale admin console.

## Services

| Service | URL |
|---|---|
| Homepage | http://homelab-1.tail53266a.ts.net:30000 |
| Gatus | :30003 |
| Hermes Agent | :30008 |
| Dozzle | :30016 |

## Good to know

- **Disk encryption:** if you encrypt the disk in the installer, the server
  waits at its own keyboard for the passphrase after every reboot.
- **No backups:** data under `/srv/homelab` on the server is **not backed up**,
  so keep the `hermes-backups` repo for now.
