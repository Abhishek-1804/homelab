variable "region" {
  type    = string
  default = "us-west-1"
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
  description = "The login user (vars.user in mise.test.toml)"
  type        = string
  default     = "abhishek"
}

variable "github_user" {
  description = "Whose GitHub SSH keys can log in, like the manual `ssh-import-id` step"
  type        = string
  default     = "Abhishek-1804"
}
