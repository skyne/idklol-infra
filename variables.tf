variable "kubeconfig_path" {
  description = "Path to the kubeconfig file Terraform should use."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Optional kubeconfig context name. Leave null to use the current context."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace for the idklol server stack."
  type        = string
  default     = "idklol"
}

variable "ingress_class_name" {
  description = "IngressClass name. k3s defaults to traefik; nginx works too."
  type        = string
  default     = "traefik"
}

variable "ingress_tls_enabled" {
  description = "Whether ingress resources should expect TLS."
  type        = bool
  default     = false
}

variable "cluster_issuer_name" {
  description = "Optional cert-manager ClusterIssuer name for ingress TLS."
  type        = string
  default     = null
}

variable "webadmin_host" {
  description = "Public hostname for the webadmin frontend."
  type        = string
  default     = "admin.idklol.local"
}

variable "keycloak_host" {
  description = "Public hostname for Keycloak."
  type        = string
  default     = "auth.idklol.local"
}

variable "chat_grpc_host" {
  description = "Public hostname for the chat gRPC service."
  type        = string
  default     = "chat.idklol.local"
}

variable "characters_grpc_host" {
  description = "Public hostname for the characters gRPC service."
  type        = string
  default     = "characters.idklol.local"
}

variable "image_pull_secret_names" {
  description = "Existing Kubernetes image pull secret names to attach to app pods."
  type        = list(string)
  default     = []
}

variable "external_postgres_host" {
  description = "Managed PostgreSQL hostname. Neon free tier is a good default choice."
  type        = string
}

variable "external_postgres_port" {
  description = "Managed PostgreSQL port."
  type        = number
  default     = 5432
}

variable "external_postgres_username" {
  description = "Managed PostgreSQL username."
  type        = string
  sensitive   = true
}

variable "external_postgres_password" {
  description = "Managed PostgreSQL password."
  type        = string
  sensitive   = true
}

variable "external_postgres_sslmode" {
  description = "SSL mode appended to generated PostgreSQL URLs."
  type        = string
  default     = "require"
}

variable "keycloak_database_name" {
  description = "Database name for Keycloak."
  type        = string
  default     = "idklol_keycloak"
}

variable "characters_database_name" {
  description = "Database name for the characters services."
  type        = string
  default     = "idklol_characters"
}

variable "npc_metadata_database_name" {
  description = "Database name for the NPC metadata service."
  type        = string
  default     = "idklol_npc_metadata"
}

variable "external_nats_url" {
  description = "Optional managed NATS URL. Leave null to deploy the in-cluster Helm chart."
  type        = string
  default     = null
  sensitive   = true
}

variable "deploy_incluster_nats" {
  description = "Deploy NATS in-cluster when external_nats_url is not provided."
  type        = bool
  default     = true
}

variable "otlp_endpoint" {
  description = "OTLP endpoint URL for external tracing. Grafana Cloud free tier: paste the OTLP gateway URL from My Account → Grafana Cloud → OpenTelemetry."
  type        = string
  default     = null
}

variable "otlp_auth_header" {
  description = "Authorization header value for the OTLP endpoint. Required for Grafana Cloud. Format: 'Basic <base64(instanceId:apiToken)>' — generate with: echo -n 'INSTANCEID:TOKEN' | base64"
  type        = string
  default     = null
  sensitive   = true
}

variable "keycloak_admin_username" {
  description = "Initial Keycloak admin username."
  type        = string
}

variable "keycloak_admin_password" {
  description = "Initial Keycloak admin password."
  type        = string
  sensitive   = true
}

variable "keycloak_chat_client_secret" {
  description = "Client secret for the idklol-chat Keycloak client."
  type        = string
  sensitive   = true
}

variable "keycloak_webadmin_client_secret" {
  description = "Client secret for the idklol-webadmin Keycloak client."
  type        = string
  sensitive   = true
}

variable "nextauth_secret" {
  description = "Secret used by NextAuth in the webadmin service."
  type        = string
  sensitive   = true
}

variable "chatserver_image" {
  description = "Container image for chatserver. Use immutable tags (sha/digest) in shared environments."
  type        = string
  default     = "ghcr.io/skyne/idklol-server-chatserver:latest"
}

variable "characters_grpc_image" {
  description = "Container image for characters-grpc. Use immutable tags (sha/digest) in shared environments."
  type        = string
  default     = "ghcr.io/skyne/idklol-server-characters-grpc:latest"
}

variable "characters_admin_image" {
  description = "Container image for characters-admin. Use immutable tags (sha/digest) in shared environments."
  type        = string
  default     = "ghcr.io/skyne/idklol-server-characters-admin:latest"
}

variable "characters_server_image" {
  description = "Container image for characters-server. Use immutable tags (sha/digest) in shared environments."
  type        = string
  default     = "ghcr.io/skyne/idklol-server-characters-server:latest"
}

variable "npc_metadata_service_image" {
  description = "Container image for npc-metadata-service. Use immutable tags (sha/digest) in shared environments."
  type        = string
  default     = "ghcr.io/skyne/idklol-server-npc-metadata-service:latest"
}

variable "npc_interactions_bridge_image" {
  description = "Container image for npc-interactions-bridge. Use immutable tags (sha/digest) in shared environments."
  type        = string
  default     = "ghcr.io/skyne/idklol-server-npc-interactions-bridge:latest"
}

variable "webadmin_image" {
  description = "Container image for webadmin. Use immutable tags (sha/digest) in shared environments."
  type        = string
  default     = "ghcr.io/skyne/idklol-server-webadmin:latest"
}

variable "ue_server_image" {
  description = "Container image for the UE dedicated server."
  type        = string
  default     = "ghcr.io/skyne/ue-server:latest"
}

variable "ue_server_map_path" {
  description = "Default map path for the UE dedicated server."
  type        = string
  default     = "/Game/ThirdPerson/Maps/ThirdPersonMap"
}

variable "ue_server_service_type" {
  description = "Service type for the UE dedicated server. LoadBalancer works best on k3s with ServiceLB or MetalLB."
  type        = string
  default     = "LoadBalancer"
}

variable "deploy_npc_interactions_bridge" {
  description = "Deploy the NPC interactions bridge. Disable it unless you have an external Ollama-compatible endpoint."
  type        = bool
  default     = false
}

variable "ollama_base_url" {
  description = "External Ollama-compatible base URL for npc-interactions-bridge."
  type        = string
  default     = ""
}

variable "ollama_model" {
  description = "Model name for npc-interactions-bridge."
  type        = string
  default     = "qwen2.5:1.5b"
}