# read by `mise run setup`
output "tailscale_server_key" {
  value     = tailscale_tailnet_key.server.key
  sensitive = true
}

output "tailscale_test_key" {
  value     = tailscale_tailnet_key.test.key
  sensitive = true
}
