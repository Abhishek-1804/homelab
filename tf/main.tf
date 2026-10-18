# A throwaway Ubuntu 26.04 server for testing the setup flow.

# Canonical publishes the current Ubuntu image ID here
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# SSH in; logins are key-only, and the server only lives for a test
resource "aws_security_group" "ssh" {
  name = "homelab-test-ssh"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "test" {
  ami                    = data.aws_ssm_parameter.ubuntu.insecure_value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.ssh.id]
  # authorize the GitHub SSH keys on first boot
  user_data = "#cloud-config\nssh_import_id: [gh:${var.github_user}]\n"
  # user_data only runs on first boot, so a change needs a new server
  user_data_replace_on_change = true
  tags                        = { Name = "homelab-test" }
}
