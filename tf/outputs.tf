output "ssh" {
  value = "ssh ubuntu@${aws_instance.test.public_ip}"
}
