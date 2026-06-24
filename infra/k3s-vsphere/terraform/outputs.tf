output "node_ips" {
  description = "Adresses statiques des noeuds K3s."
  value       = { for name, node in var.nodes : name => node.ipv4_address }
}

output "server_ip" {
  value = var.nodes["k3s-server-1"].ipv4_address
}

output "kubeconfig_command" {
  value = "powershell -File ../scripts/Get-Kubeconfig.ps1 -ServerIp ${var.nodes["k3s-server-1"].ipv4_address}"
}

output "cluster_validation_command" {
  value = "ssh ubuntu@${var.nodes["k3s-server-1"].ipv4_address} sudo k3s kubectl get nodes -o wide"
}
