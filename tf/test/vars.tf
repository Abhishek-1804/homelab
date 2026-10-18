variable "region" {
  type    = string
  default = "us-west-1"
}

variable "instance_type" {
  description = "t3.small (2 GiB) is the smallest that runs k3s"
  type        = string
  default     = "t3.small"
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
