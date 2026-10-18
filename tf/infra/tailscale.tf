# Who can reach what on the tailnet. Your own devices reach everything;
# servers (tag:homelab) reach each other but can never open a connection to
# your devices. This replaces the policy edited in the admin console.
resource "tailscale_acl" "policy" {
  overwrite_existing_content = true
  acl = jsonencode({
    tagOwners = {
      "tag:homelab" = ["autogroup:admin"]
    }
    grants = [
      { src = ["autogroup:member"], dst = ["*"], ip = ["*"] },
      { src = ["tag:homelab"], dst = ["tag:homelab"], ip = ["*"] },
    ]
  })
}

# Joins a server as tag:homelab without a login URL (`mise run setup`).
# Tagged devices never have to log in again. A key lasts at most 90 days;
# after that, the next `mise run tf infra apply` makes a new one.
resource "tailscale_tailnet_key" "server" {
  description         = "homelab servers"
  tags                = ["tag:homelab"]
  reusable            = true
  preauthorized       = true
  expiry              = 7776000 # 90 days
  recreate_if_invalid = "always"
  depends_on          = [tailscale_acl.policy] # the tag must exist first
}

# The same for EC2 test servers (`mise run setup --test`), except they are
# ephemeral: Tailscale removes them once they go offline.
resource "tailscale_tailnet_key" "test" {
  description         = "homelab test servers"
  tags                = ["tag:homelab"]
  reusable            = true
  ephemeral           = true
  preauthorized       = true
  expiry              = 7776000
  recreate_if_invalid = "always"
  depends_on          = [tailscale_acl.policy]
}
