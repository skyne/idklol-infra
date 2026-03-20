# Deployment Guide

Full end-to-end deployment of the idklol stack on a Hetzner VPS.

**What runs where:**
- **Hetzner cx33** (~€6.34/mo) — k3s single-node cluster: Keycloak, NATS, all app services, UE server
- **Neon** (free tier) — PostgreSQL for Keycloak, characters, npc-metadata
- **Grafana Cloud** (free tier, optional) — traces, logs, metrics via OTLP

---

## Prerequisites

Install on your local machine before starting:

```bash
# macOS
brew install terraform
brew install gh          # GitHub CLI (for CI image pushes)
```

You also need:
- A [Hetzner Cloud](https://www.hetzner.com/cloud) account
- An SSH key pair (`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519` if you don't have one)
- Docker running locally (for building service images if not using CI)

---

## Step 1 — Managed Postgres (Neon free tier)

1. Sign up at **https://neon.tech**
2. Create a new **Project** in region **eu-central-1** (closest to Hetzner `fsn1`)
3. In the project dashboard, create three databases:
   - `idklol_keycloak`
   - `idklol_characters`
   - `idklol_npc_metadata`
4. Go to **Project Settings → Connection Details** and note down:
   - Host (looks like `ep-something.eu-central-1.aws.neon.tech`)
   - Username and password

> The `neon` free tier gives you 0.5 vCPU, 1 GB RAM, 3 GB storage and scales to zero when idle — plenty for dev/playtest.

---

## Step 2 — Observability (Grafana Cloud free tier, optional)

Skip this step if you don't need traces/logs yet. You can add it later without redeploying.

1. Sign up at **https://grafana.com/auth/sign-up/create-user**
2. Go to **My Account → Grafana Cloud → OpenTelemetry**
3. Copy the **OTLP endpoint URL** (looks like `https://otlp-gateway-prod-eu-west-0.grafana.net/otlp`)
4. Create an **API token** with scopes: `MetricsPublisher`, `LogsPublisher`, `TracesPublisher`
5. Generate your auth header:

```bash
echo -n "YOUR_INSTANCE_ID:YOUR_API_TOKEN" | base64
# → paste the output as the otlp_auth_header value: "Basic <output>"
```

---

## Step 3 — Provision the VPS and k3s cluster

```bash
cd hetzner
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:

| Variable | Where to get it |
|---|---|
| `hcloud_token` | Hetzner Cloud Console → Security → API Tokens → Create token with **Read & Write** |
| `ssh_public_key` | `cat ~/.ssh/id_ed25519.pub` |
| `ssh_private_key_path` | `~/.ssh/id_ed25519` |
| `create_ssh_key` | Set to `false` if a key named `idklol-k3s-key` already exists in your Hetzner project |

Then apply:

```bash
terraform init
terraform apply
```

Terraform will:
1. Create a `cx33` server in Frankfurt with Ubuntu 24.04
2. Install k3s (with Traefik ingress + ServiceLB) via cloud-init
3. Poll until k3s is ready, then fetch `/etc/rancher/k3s/k3s.yaml` to `./generated/kubeconfig.yaml`

This takes ~3 minutes. At the end you'll see the server IP:

```bash
terraform output server_ipv4
```

---

## Step 4 — Configure the app stack

```bash
cd ..   # back to infra repo root
cp terraform.tfvars.example prod.tfvars
```

Edit `prod.tfvars`:

```hcl
# Point hostnames at your server IP (you'll set DNS in Step 5)
webadmin_host        = "admin.yourdomain.com"
keycloak_host        = "auth.yourdomain.com"
chat_grpc_host       = "chat.yourdomain.com"
characters_grpc_host = "characters.yourdomain.com"

# Neon credentials from Step 1
external_postgres_host     = "ep-something.eu-central-1.aws.neon.tech"
external_postgres_username = "your-neon-user"
external_postgres_password = "your-neon-password"

# Generate strong secrets
keycloak_admin_username        = "idklol-admin"
keycloak_admin_password        = "$(openssl rand -base64 24)"
keycloak_chat_client_secret    = "$(openssl rand -base64 24)"
keycloak_webadmin_client_secret = "$(openssl rand -base64 24)"
nextauth_secret                = "$(openssl rand -base64 32)"

# Grafana Cloud from Step 2 (leave null to disable)
otlp_endpoint    = "https://otlp-gateway-prod-eu-west-0.grafana.net/otlp"
otlp_auth_header = "Basic <your-base64-token>"
```

Generate the secrets in your terminal first:

```bash
echo "keycloak_admin_password        = \"$(openssl rand -base64 24)\""
echo "keycloak_chat_client_secret    = \"$(openssl rand -base64 24)\""
echo "keycloak_webadmin_client_secret = \"$(openssl rand -base64 24)\""
echo "nextauth_secret                = \"$(openssl rand -base64 32)\""

# set a non-default admin username
echo "keycloak_admin_username        = \"idklol-admin\""
```

---

## Step 5 — Set DNS

Point the four A records at the server IP you got from Step 3:

```
admin.yourdomain.com       →  <server_ipv4>
auth.yourdomain.com        →  <server_ipv4>
chat.yourdomain.com        →  <server_ipv4>
characters.yourdomain.com  →  <server_ipv4>
```

DNS propagation typically takes 1–5 minutes with a short TTL.

---

## Step 5.5 — Add GHCR pull secret (required for `ue-server`)

`ue-server` is pulled from `ghcr.io/skyne/ue-server:latest`, so Kubernetes needs an image pull secret.

1. Create a GitHub Personal Access Token that can pull packages:
   - Classic token scope: `read:packages`
   - Fine-grained token: package read access for the repository that publishes `ue-server`

2. Create/update the secret in the `idklol` namespace:

```bash
export KUBECONFIG=$(cd hetzner && terraform output -raw kubeconfig_path)
export GHCR_USER="YOUR_GITHUB_USERNAME"
export GHCR_PAT="YOUR_GITHUB_PAT"

kubectl -n idklol create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username="$GHCR_USER" \
  --docker-password="$GHCR_PAT" \
  --dry-run=client -o yaml | kubectl apply -f -
```

3. Ensure your app tfvars includes:

```hcl
image_pull_secret_names = ["ghcr-pull-secret"]
```

---

## Step 6 — Deploy the app stack

```bash
KUBECONFIG=$(cd hetzner && terraform output -raw kubeconfig_path)

terraform init
terraform apply \
  -var-file=prod.tfvars \
  -var "kubeconfig_path=$KUBECONFIG" \
  -var "kube_context="
```

This applies:
- Kubernetes namespace + shared secret
- Keycloak Helm release (Bitnami) — realm imported on first boot
- NATS Helm release (in-cluster)
- All app services via the local `idklol-stack` Helm chart

Takes ~5 minutes. Keycloak takes the longest on first start (it runs DB migrations).

---

## Step 7 — Verify

```bash
export KUBECONFIG=$(cd hetzner && terraform output -raw kubeconfig_path)

# All pods should be Running/Completed
kubectl -n idklol get pods

# Keycloak logs (takes ~2 min to fully start)
kubectl -n idklol logs -l app.kubernetes.io/name=keycloak --tail=30

# Check services are reachable
curl -s https://auth.yourdomain.com/realms/idklol/.well-known/openid-configuration | jq .issuer
```

Open **https://admin.yourdomain.com** — you should see the webadmin login page, which redirects to Keycloak.

---

## Step 8 — Connect the game client

Launch with args that point at your deployed stack:

```
-KeycloakUrl=https://auth.yourdomain.com \
-GrpcDefaultEndpoint=characters.yourdomain.com:443 \
-GrpcChatEndpoint=chat.yourdomain.com:443 \
-ServerAddress=<server_ipv4>:7777
```

---

## TLS (optional but recommended)

Install cert-manager and set `ingress_tls_enabled = true` + `cluster_issuer_name = "letsencrypt-prod"` in your tfvars, then re-apply.

Quick cert-manager install:

```bash
export KUBECONFIG=$(cd hetzner && terraform output -raw kubeconfig_path)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

Then create a ClusterIssuer (replace the email):

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: you@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
```

Re-apply the app stack with TLS enabled.

---

## Teardown

```bash
# Remove app stack
terraform destroy -var-file=prod.tfvars -var "kubeconfig_path=$(cd hetzner && terraform output -raw kubeconfig_path)"

# Remove the VPS
cd hetzner && terraform destroy
```

> Neon and Grafana Cloud resources are managed outside Terraform — delete them from their respective dashboards if no longer needed.