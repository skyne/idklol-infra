output "namespace" {
  description = "Namespace where the stack is deployed."
  value       = kubernetes_namespace_v1.stack.metadata[0].name
}

output "webadmin_url" {
  description = "Public URL for the webadmin frontend."
  value       = "${local.public_scheme}://${var.webadmin_host}"
}

output "keycloak_url" {
  description = "Public URL for Keycloak."
  value       = "${local.public_scheme}://${var.keycloak_host}"
}

output "chat_grpc_host" {
  description = "Public hostname for the chat gRPC ingress."
  value       = var.chat_grpc_host
}

output "characters_grpc_host" {
  description = "Public hostname for the characters gRPC ingress."
  value       = var.characters_grpc_host
}

output "nats_url" {
  description = "Resolved NATS URL used by the workloads."
  value       = local.nats_url
  sensitive   = true
}