variable "region" {
  type    = string
  default = "us-west-1"
}

variable "servers" {
  description = "One EC2 server per name: the control plane first, then the nodes"
  type        = list(string)
  default     = ["homelab-1", "homelab-2", "homelab-3"]
}

variable "instance_type" {
  description = "t3.medium (4 GiB): a t3.small (2 GiB) stopped responding running k3s plus Hermes"
  type        = string
  default     = "t3.medium"
}

variable "disk_size" {
  description = "GiB; the default 8 leaves too little room for container images"
  type        = number
  default     = 20
}

variable "username" {
  description = "The login user, the same as on the real server"
  type        = string
  default     = "abhishek"
}

variable "github_user" {
  description = "Whose GitHub SSH keys can log in, like the manual `ssh-import-id` step"
  type        = string
  default     = "Abhishek-1804"
}
