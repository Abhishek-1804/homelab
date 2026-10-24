# one `ssh user@ip` per server
output "ssh" {
  value = { for name, server in aws_instance.test : name => "ssh ${var.username}@${server.public_ip}" }
}
