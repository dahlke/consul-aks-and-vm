output "kube_config" {
  value = "${azurerm_kubernetes_cluster.example.kube_config_raw}"
}

output "vm_public_ip" {
  value = "${azurerm_public_ip.example.ip_address}"
}