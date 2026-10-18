terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  backend "s3" {
    bucket       = "abhishek1804-homelab-tfstate" # created by tf/state
    key          = "test.tfstate"
    region       = "us-west-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
}
