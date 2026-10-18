# homelab

A k3s cluster on a headless server, hosting the Hermes agent. Everything is
managed with [mise](https://mise.jdx.dev) from the laptop.

| File | What it is |
|---|---|
| `mise.toml` | Laptop: tools, the server inventory, tasks |
| `server/mise.toml` | Everything on a server: packages, SSH, firewall, k3s. `server/` is the only folder sent to servers |
| `manifests/` | What runs in the cluster |
| `tf/` | Terraform: the state bucket, the AWS budget and Tailscale, and EC2 test servers |

## Requirements

### Accounts

| Account | Used for |
|---|---|
| GitHub | This repo; servers import your SSH key from it |
| Tailscale | The private network you reach the servers through, managed in `tf/infra` |
| 1Password | Every secret (the `homelab` Environment) |
| AWS | Terraform state, the budget alert, test servers, through `aws login` (no stored keys) |

### On the laptop

Install these yourself:

| Tool | Why |
|---|---|
| [mise](https://mise.jdx.dev) | Runs every task and installs the tools below |
| Tailscale | Reaches the servers after setup |
| An SSH key, also added to GitHub | Logging in to the servers. Kept in 1Password: Settings → Developer → **Use the SSH agent**, and `IdentityAgent ~/.1password/agent.sock` in `~/.ssh/config` |
| 1Password desktop app | Mounts the secrets as `.env` files (Developer → Environments) and holds the SSH key |
| AWS CLI | Signs in to AWS for Terraform |

mise installs the rest at the versions pinned in `mise.toml`: `kubectl` and
`terraform` with `mise install`, and `yq` and `k9s` the first time their tasks run.

### Before running tasks

| Check | Needed for | How |
|---|---|---|
| Your SSH key is on GitHub | Every server: they authorize the keys at `github.com/<github-user>.keys` | GitHub → Settings → SSH keys. `tf/test/vars.tf` sets `github_user` |
| Signed in to AWS | `tf`, and `setup` (it reads the Tailscale key from Terraform state) | `mise run tf-login`; check with `aws sts get-caller-identity` |
| Tailscale is connected | `up`, `ping`, `kubeconfig`, `deploy` | `tailscale status` |
| 1Password is unlocked | `deploy` and `tf infra` (they read `.env`) | Open the desktop app |

### On a server

The only manual step is installing **Ubuntu Server** (24.04 or 26.04 LTS) with
two things working:

- **Wi-Fi:** connected, so the server has a LAN IP and internet.
- **SSH:** `openssh-server` running, with your key authorized
  (`ssh-import-id gh:<github-user>`), so `ssh <user>@<lan-ip>` works without a password.

Everything else is code. `server/mise.toml` installs `openssh-server`,
`tailscale`, `ufw` and `unattended-upgrades`, and then k3s at the version
pinned there.

## Setting up a server

Once `tf/infra` is applied (see [Terraform](#terraform-tf)), from the laptop:

```bash
mise run setup homelab-1 abhishek@192.168.1.50   # first run, over the LAN
mise run up                                       # over Tailscale; turns the firewall on
mise run deploy                                   # secrets + apps
```

`setup` sets the hostname, installs the packages, sets SSH to keys only, keeps
the laptop awake with the lid closed, joins Tailscale as `tag:homelab` with a
key from `tf/infra` (no login URL) and installs k3s. `up` repeats all of that
over Tailscale and adds the firewall. After that, **the server is reachable
only over Tailscale.** Run `mise run up` any time to re-apply.

| Task | Does |
|---|---|
| `mise run ping` | Every server: up or down, over Tailscale and SSH |
| `mise run kubeconfig` | Lets `kubectl`/`k9s` on the laptop reach the cluster |
| `mise run k9s` | Opens [k9s](https://k9scli.io) on the cluster |

To add a server, add a block to `mise.toml`:

```toml
[bootstrap.remote.hosts.homelab-2]
host              = "homelab-2"      # its Tailscale name
bootstrap_command = "curl -fsSL https://mise.run | sh"
```

## Secrets

All app secrets live in one **1Password Environment**, `homelab`. The desktop
app mounts it as `.env` in this repo, which is gitignored and never sent to
the servers. `mise run deploy` loads it into the `homelab-env` Kubernetes
Secret, which k3s stores encrypted. Hermes gets each line as an env var.

**Any pod given this Secret sees every value in it**, so only put in secrets
its users may all see. Today that's just Hermes. The one exception is
`TAILSCALE_*`: Terraform's admin access to the tailnet, which `deploy` leaves
out of the Secret and `mise run tf infra` alone reads.

To set it up in 1Password: open **Developer → Environments**, create `homelab`,
and add the variables (e.g. `CLAUDE_CODE_OAUTH_TOKEN`). Then add the
destination **Local .env file** with the path `.env` in this repo.

| Task | Does |
|---|---|
| `mise run deploy` | Pushes the current secrets to the cluster (after any change in 1Password) |
| `mise run env-local` | Writes `.env.local`: the variable names in `.env`, without values |

## Terraform (`tf/`)

Three stacks, each run with `mise run tf <stack> <command>`, e.g.
`mise run tf infra plan`:

| Stack | Holds | State |
|---|---|---|
| `tf/state` | The S3 bucket every other stack keeps its state in | On the laptop (gitignored) |
| `tf/infra` | The AWS budget alert; the Tailscale access rules and join keys | S3 |
| `tf/test` | A throwaway EC2 server for testing the setup flow | S3 |

### AWS login

`aws login` signs you in through the browser as an IAM user, and the CLI gets
short-lived credentials. No AWS keys are stored anywhere, and the root user is
kept for billing only. Set it up once:

1. As root, in **IAM** → **Users**, create `akdp` with console access and the
   `PowerUserAccess` policy (everything except IAM). Sign in as it with
   your account ID and add MFA.
2. `mise run tf-login` and sign in as `akdp`. That saves the `homelab`
   profile in `~/.aws/config` (`mise.toml` sets `AWS_PROFILE=homelab` for
   this repo). Run it again whenever the credentials expire.

### Tailscale

`tf/infra` replaces the tailnet's access rules: your devices reach everything,
and servers (`tag:homelab`) reach each other but can never open a connection
to your devices. It also makes the keys `setup` joins servers with. Tagged
servers never have to log in again. Test servers join as *ephemeral*, so
Tailscale removes them once they go offline.

Terraform talks to Tailscale through an OAuth client. Set it up once:

1. In the [admin console](https://login.tailscale.com/admin), open **Access
   controls** and add the tag, so the OAuth client can be given it:
   ```json
   "tagOwners": { "tag:homelab": ["autogroup:admin"] },
   ```
2. **Settings → Trust credentials → Credential → OAuth** with these scopes:
   - **Policy File:** write
   - **Auth Keys:** write, with the tag `tag:homelab`
3. Add the client's ID and secret to the `homelab` Environment as
   `TAILSCALE_OAUTH_CLIENT_ID` and `TAILSCALE_OAUTH_CLIENT_SECRET`.

### First time, in order

```bash
mise run tf-login
mise run tf state init && mise run tf state apply   # the S3 bucket
mise run tf infra init && mise run tf infra apply   # budget + Tailscale
mise run tf test init                               # once, before the first test server
```

The budget is `homelab-monthly` in code, emailing the `alert_email` in
`tf/infra/consts.tf`; delete any budget made by hand in the console, or you'll get
every alert twice.

The Tailscale join keys last 90 days. After that, `mise run tf infra apply`
makes new ones.

### Testing the setup flow on EC2

```bash
mise run tf test apply                            # prints `ssh abhishek@<ip>`
mise run setup --test homelab-1 abhishek@<ip>     # then up, deploy, as above
mise run tf test destroy                          # when done
```

The server lets in your GitHub SSH keys (key import can take a minute after
boot) and costs about $0.025/hour as a `t3.small`. Settings such as the
instance type are in `tf/test/vars.tf`.

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
