terraform {
  required_providers {
    aws       = { source = "hashicorp/aws", version = "~> 6.0" }
    tailscale = { source = "tailscale/tailscale", version = "~> 0.29" }
  }

  backend "s3" {
    bucket       = "abhishek1804-homelab-tfstate" # created by tf/state
    key          = "infra.tfstate"
    region       = "us-west-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-west-1"
}

# Reads TAILSCALE_OAUTH_CLIENT_ID and TAILSCALE_OAUTH_CLIENT_SECRET, which
# `mise run tf` loads from .env
provider "tailscale" {}
