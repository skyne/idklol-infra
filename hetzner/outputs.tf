output "server_name" {
  description = "Hetzner server name running k3s."
  value       = hcloud_server.k3s.name
}

output "server_ipv4" {
  description = "Public IPv4 of the k3s node."
  value       = hcloud_server.k3s.ipv4_address
}

output "kubeconfig_path" {
  description = "Local kubeconfig path written by Terraform."
  value       = local.kubeconfig_output_path
}

output "next_step_hint" {
  description = "Next command to deploy the application stack using this cluster."
  value       = "terraform -chdir=.. apply -var-file=dev.tfvars -var 'kubeconfig_path=${local.kubeconfig_output_path}'"
}