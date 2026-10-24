output "ssh" {
  value = "ssh ${var.username}@${aws_instance.test.public_ip}"
}
