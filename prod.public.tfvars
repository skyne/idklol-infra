# Public, non-sensitive production Terraform variables.
# Keep secrets in a local `prod.secrets.tfvars` file and in GitHub secret `PROD_TFVARS_B64`.

# Kubernetes access
kubeconfig_path = "~/.kube/config"
# Set to null when using the generated kubeconfig from ./hetzner
kube_context = null

# Networking
namespace           = "idklol"
ingress_class_name  = "traefik"
ingress_tls_enabled = false

webadmin_host        = "admin.skyne.duckdns.org"
keycloak_host        = "auth.skyne.duckdns.org"
chat_grpc_host       = "chat.skyne.duckdns.org"
characters_grpc_host = "characters.skyne.duckdns.org"

# Managed PostgreSQL (non-secret settings)
external_postgres_host    = "ep-restless-haze-al3fbz0z-pooler.c-3.eu-central-1.aws.neon.tech"
external_postgres_port    = 5432
external_postgres_sslmode = "require"

keycloak_database_name     = "keycloak"
characters_database_name   = "characters"
npc_metadata_database_name = "npc"

# Messaging
# Leave empty to use the in-cluster NATS Helm release.
external_nats_url     = null
deploy_incluster_nats = true

# Observability
otlp_endpoint = null

# Optional private registry pull secrets already present in the namespace
image_pull_secret_names = ["ghcr-pull-secret"]

# UE dedicated server
ue_server_service_type = "LoadBalancer"

# Optional NPC bridge
deploy_npc_interactions_bridge = false
ollama_base_url                = ""
ollama_model                   = "qwen2.5:1.5b"

# Deployment images (immutable tags)
chatserver_image = "ghcr.io/skyne/idklol-server-chatserver:sha-af3ce47"
characters_grpc_image = "ghcr.io/skyne/idklol-server-characters-grpc:sha-af3ce47"
characters_admin_image = "ghcr.io/skyne/idklol-server-characters-admin:sha-af3ce47"
characters_server_image = "ghcr.io/skyne/idklol-server-characters-server:sha-af3ce47"
npc_metadata_service_image = "ghcr.io/skyne/idklol-server-npc-metadata-service:sha-af3ce47"
npc_interactions_bridge_image = "ghcr.io/skyne/idklol-server-npc-interactions-bridge:sha-af3ce47"
webadmin_image = "ghcr.io/skyne/idklol-server-webadmin:sha-af3ce47"
ue_server_image = "ghcr.io/skyne/ue-server:sha-a4d0788"