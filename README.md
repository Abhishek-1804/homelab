# homelab

A single-node k3s cluster on a headless laptop (`homelab-1`), hosting the
Hermes agent. Everything is managed with [mise](https://mise.jdx.dev) from your
laptop, and the server is reachable only over Tailscale.

| File | What it is |
|---|---|
| `mise.toml` | Laptop: tools and tasks; `[vars]` names the server (`control_plane`) and its login `user` |
| `mise.test.toml` | Loaded with `MISE_ENV=test`: points every task at an EC2 test server instead |
| `server/mise.toml` | Everything on the server: packages, Tailscale, SSH, firewall, k3s. `server/` is the only folder sent to it |
| `manifests/` | What runs in the cluster |
| `kind-config.yaml` | A local cluster for testing `manifests/` before they go to the server |
| `tf/` | Terraform: the state bucket, the AWS budget and Tailscale, and EC2 test servers |
| `hack/hermes-restore.sh` | Restores a Hermes backup zip |

## Requirements

### Accounts

| Account | Used for |
|---|---|
| GitHub | This repo; Hermes's backups (`hermes-backups`, private); EC2 test servers import your SSH key from it |
| Tailscale | The private network you reach the server through, managed in `tf/infra` |
| 1Password | Every secret (the `homelab` Environment) and your SSH key |
| AWS | Terraform state, the budget alert, test servers, through `aws login` (no stored keys) |

### On the laptop

Install these yourself:

| Tool | Why |
|---|---|
| [mise](https://mise.jdx.dev) | Runs every task and installs the tools below |
| Tailscale | Reaches the server |
| 1Password desktop app | Mounts the secrets as `.env` (Developer → Environments) and holds your SSH key: Settings → Developer → **Use the SSH agent**, and `IdentityAgent ~/.1password/agent.sock` in `~/.ssh/config` |
| AWS CLI | Signs in to AWS for Terraform |

`mise install` installs the rest, listed in `[tools]` at the top of
`mise.toml`: `k9s`, `kind`, `kubectl` and `terraform`. All are `latest` except
`kubectl`, which must match the k3s version.

### Before running tasks

| Check | Needed for | How |
|---|---|---|
| 1Password is unlocked | `bootstrap` (your SSH key), `deploy`, `tf infra`, `generate-env-local` (they read `.env`) | Open the desktop app. **While it's locked, anything reading `.env` hangs without an error** |
| Signed in to AWS | `tf`, and `bootstrap` for a new server (it reads the Tailscale key from Terraform state) | `aws login`; check with `aws sts get-caller-identity` |
| Tailscale is connected | `bootstrap`, `kubeconfig`, `deploy` | `tailscale status` |

### On the server

Install **Ubuntu Server** (24.04 or 26.04 LTS) with:

- **Wi-Fi** connected, so it has a LAN IP and internet.
- **Install OpenSSH server** ticked. Nothing else: no SSH key import, no other
  packages. Password logins are fine; `bootstrap` turns them off.
- The user you create there set as `user` in `mise.toml` (today `akdp-latitude`).

Find its LAN IP with `ip -4 a` on it, or `nmap -p22 --open <your-lan>/24` from
the laptop.

## Setting up the server

Once `tf/infra` is applied (see [Terraform](#terraform-tf)), from the laptop:

```bash
mise run bootstrap 10.64.82.151   # a new (or reinstalled) server: its LAN IP
mise run deploy                   # secrets + apps
```

`bootstrap` on a new server:

1. Copies your SSH key (asks for the server password once) and allows `sudo`
   without a password (asks for it once more), so the rest runs unattended.
2. Sets the hostname to `homelab-1` and drops a Tailscale join key from
   `tf/infra` on it.
3. **Over the LAN:** applies `server/mise.toml` except the firewall: packages,
   joining Tailscale as `tag:homelab` (no login URL), SSH keys only, no sleep
   with the lid closed, and k3s.
4. **Over Tailscale:** applies everything again, now with the firewall. mise
   won't firewall off the session it runs over, which is why the firewall
   waits for this pass.

After that, **the server is reachable only over Tailscale**. `mise run
bootstrap` with no arguments re-applies everything over Tailscale; run it after
changing `server/mise.toml`. Upgrading k3s is changing `k3s_version` there and
running it.

To use `kubectl` or [k9s](https://k9scli.io) on the cluster, copy its
kubeconfig into the project and point `KUBECONFIG` at it:

```bash
mise run sync-kubeconfig                    # writes .kube/kubeconfig-server
export KUBECONFIG=$PWD/.kube/kubeconfig-server
k9s
```

| Cluster | Kubeconfig | Written by |
|---|---|---|
| The server | `.kube/kubeconfig-server` | `mise run sync-kubeconfig` (and `deploy`) |
| EC2 test server | `.kube/kubeconfig-test-server` | `MISE_ENV=test mise run sync-kubeconfig` |
| Local kind | `.kube/kubeconfig-kind-local` | `mise run kind-deploy` |

### What's reachable

Checked with a full scan from another device on the same Wi-Fi: every TCP
port is dropped, and the only open UDP port is Tailscale's (41641), which
ignores anything not encrypted with a key from your tailnet. IPv6 gets the
same deny-by-default.

- **SSH:** only from Tailscale addresses, keys only, no root login.
- **Apps and the k3s API:** only on the Tailscale interface; NodePorts answer
  only on the Tailscale address.
- **Tailscale access rules (`tf/infra`):** your devices reach the server; the
  server can't open connections to your devices.

## Testing manifests locally

To try changes to `manifests/` without the server, run them in
[kind](https://kind.sigs.k8s.io), a Kubernetes cluster in Docker on the laptop.
Server setup itself (Tailscale, firewall, k3s) is tested on EC2 instead; see
[Testing the setup flow on EC2](#testing-the-setup-flow-on-ec2).

| Task | Does |
|---|---|
| `mise run kind-deploy` | Creates the cluster if needed, writes `.kube/kubeconfig-kind-local` and applies the secrets and every manifest. Apps are on `http://localhost:<port>`, e.g. Homepage on :30000 |
| `mise run kind-down` | Deletes the cluster and everything in it |

The secrets are the real ones from `.env`, so Hermes connects your actual
Discord bot. Don't leave it running while Hermes also runs on the server.

## Secrets

All secrets live in one **1Password Environment**, `homelab`. The desktop app
mounts it as `.env` in this repo, which is gitignored and never sent to the
server. `mise run deploy` loads it into the `homelab-env` Kubernetes Secret,
which k3s stores encrypted, leaving out `TAILSCALE_*` (Terraform's admin access
to the tailnet, read only by `mise run tf infra`).

Each app gets only the variables its manifest names (`secretKeyRef`), never the
whole Secret. Hermes gets:

| Variable | What |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Its Claude login; shared by every AI app |
| `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` | The dashboard password (user `abhishek`, set in `manifests/ai/hermes-agent.yaml`) |
| `HERMES_DASHBOARD_BASIC_AUTH_SECRET` | Keeps you logged in across restarts: any random string, e.g. from `openssl rand -base64 32` |
| `HERMES_BACKUP_PAT` | A fine-grained GitHub token, *Contents: read and write* on `hermes-backups` only, for Hermes's own backups |

Everything else Hermes uses (the Discord bot token, allowed Discord users, the X
login, skill keys) is set in its dashboard and kept in its data folder, so a
restore brings it back. Allow Discord users by their
numeric ID (Developer Mode → right-click → Copy User ID), not username: a
username needs the bot's Server Members intent, and without it the bot never
comes online. **Never enter the keys above
in the dashboard:** Hermes's own `.env` wins over the pod's environment, so a
copy there silently replaces 1Password's.

To set it up in 1Password: open **Developer → Environments**, create `homelab`,
add the variables, then add the destination **Local .env file** with the path
`.env` in this repo.

| Task | Does |
|---|---|
| `mise run deploy` | Applies the secrets and every manifest; restarts Hermes only if its secrets changed |
| `mise run generate-env-local` | Writes `.env.local`: the variable names in `.env`, without values |

## Hermes backups and restore

Hermes backs itself up to the private `hermes-backups` repo with
`HERMES_BACKUP_PAT`; that job is set up inside Hermes, not here (not yet done). To restore a
backup (e.g. on a fresh server, after `deploy`):

```bash
gh release download <tag> -R Abhishek-1804/hermes-backups
hack/hermes-restore.sh hermes-backup-<date>.zip
```

The script imports the zip, removes any of the keys above from Hermes's own
`.env` so 1Password's win, turns off profile multiplexing (which would make
Hermes ignore the pod's environment) and restarts Hermes. Without a zip, it
does only the last three.

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
2. `aws login` and sign in as `akdp`. That saves the `homelab`
   profile in `~/.aws/config` (`mise.toml` sets `AWS_PROFILE=homelab` for
   this repo). Run it again whenever the credentials expire.

### Tailscale

`tf/infra` replaces the tailnet's access rules: your devices reach everything,
and servers (`tag:homelab`) reach each other but can never open a connection
to your devices. It also makes the keys `bootstrap` joins servers with. Tagged
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
aws login
mise run tf state init && mise run tf state apply   # the S3 bucket
mise run tf infra init && mise run tf infra apply   # budget + Tailscale
mise run tf test init                               # once, before the first test server
```

The budget is `homelab-monthly` in code, emailing the `alert_email` in
`tf/infra/consts.tf`; delete any budget made by hand in the console, or you'll
get every alert twice.

The Tailscale join keys last 90 days. After that, `mise run tf infra apply`
makes new ones.

### Testing the setup flow on EC2

`MISE_ENV=test` loads `mise.test.toml`, which points every task at the test
server, `homelab-test` (user `abhishek`, its own kubeconfig
`.kube/kubeconfig-test-server`), instead of the real one. It joins Tailscale
as *ephemeral*, so it leaves the tailnet once it's gone.

```bash
mise run tf test apply                         # prints `ssh abhishek@<ip>`
MISE_ENV=test mise run bootstrap <ip>
MISE_ENV=test mise run deploy
ssh abhishek@homelab-test sudo tailscale logout && mise run tf test destroy   # when done
```

The server lets in your GitHub SSH keys (key import can take a minute after
boot) and costs about $0.04/hour as a `t3.medium`. Settings such as the
instance type are in `tf/test/vars.tf`.

## Services

On your tailnet:

| Service | URL |
|---|---|
| Homepage | http://homelab-1:30000 |
| Gatus | http://homelab-1:30003 |
| Hermes (dashboard, log in as `abhishek`) | http://homelab-1:30008 |
| Pages Hermes serves itself (it must listen on `0.0.0.0:3000`) | http://homelab-1:30009 |
| Dozzle | http://homelab-1:30016 |

## Good to know

- **Starting over:** `mise run bootstrap` fixes most broken configs. For a
  broken cluster, `ssh akdp-latitude@homelab-1 sudo /usr/local/bin/k3s-uninstall.sh`, then
  `bootstrap` again; for a broken OS, reinstall Ubuntu and `mise run bootstrap
  <lan-ip>`. Before reusing the name, remove the old `homelab-1` from the
  Tailscale admin console, or the new one becomes `homelab-1-1`.
- **Data:** everything apps keep is under `/srv/homelab` on the server. Only
  Hermes's own backups cover it, once you set them up in Hermes; Gatus's
  history isn't backed up.
- **Disk encryption:** if you encrypt the disk in the installer, the server
  waits at its own keyboard for the passphrase after every reboot.
