# idklol Kubernetes Infra

This folder contains a Terraform root plus a local Helm chart for deploying the `idklol-server` stack onto a Kubernetes cluster.

The stack is designed for a small dev environment first:

- Managed PostgreSQL by default
- Managed Redis reserved for future services, but not used by the current stack yet
- External OTLP/Grafana Cloud if you want traces without running observability in-cluster
- In-cluster NATS by default, because a reliable always-free managed NATS offering is not a good baseline to build around

## Recommended Free-Tier SaaS

- PostgreSQL: Neon free tier
- Logs / traces / metrics: Grafana Cloud free tier
- NATS: use the included Helm release unless you already have a managed NATS account

## What Gets Deployed

- Bitnami Keycloak Helm chart, backed by managed PostgreSQL
- NATS Helm chart if you do not provide an external NATS URL
- Local Helm chart for:
  - `chatserver`
  - `characters-grpc`
  - `characters-admin`
  - `characters-server`
  - `npc-metadata-service`
  - `webadmin`
  - `ue-server`
  - optional `npc-interactions-bridge`

The current scaffold does not deploy Loki, Tempo, Prometheus, Grafana, or Postgres inside the cluster. That is deliberate for a small dev VPS.

## VPS Sizing

For a single-node dev-only Kubernetes cluster running this stack with managed Postgres and without Ollama on the same machine:

- Minimum practical: `4 vCPU / 12 GB RAM / 120 GB NVMe`
- Better: `6 vCPU / 16 GB RAM / 160 GB NVMe`
- If you also want in-cluster observability or local LLM workloads: `8 vCPU / 24-32 GB RAM`

The `2 vCPU / 6 GB RAM / 50 GB` VPS in your screenshot is too small for a comfortable experience with Keycloak, the UE server, and Kubernetes overhead.

## Quick Start

1. Copy `terraform.tfvars.example` to a local `.tfvars` file.
2. Fill in your managed PostgreSQL credentials and app secrets.
3. Make sure your cluster has an ingress controller.
4. Apply the Terraform root.

Example:

```bash
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

## CI/CD Deployment Flow (Recommended)

This repo now supports a GitOps-style promotion flow with immutable image tags:

1. `idklol-server` builds and pushes service images tagged as `sha-<short-commit>`.
2. `idklol-server` triggers `promote-server-images.yml` in this repo.
3. `idklol-client` UE pipeline triggers `promote-ue-image.yml` in this repo.
4. Promotion workflow updates `prod.tfvars` image variables and opens a PR.
5. Merging the PR triggers `terraform-deploy.yml` apply on `main`.

This gives reproducible deploys and easy rollbacks (revert the promotion PR).

### Required GitHub Secrets

- In `idklol-server`:
  - `INFRA_REPO_TOKEN`: token with permission to dispatch workflows in `skyne/idklol-infra`.
- In `idklol-client`:
  - `INFRA_REPO_TOKEN`: same as above, used by UE workflow dispatch.
- In `idklol-server` and `idklol-client` (optional repository variable):
  - `INFRA_AUTOMERGE`: set to `true` to request PR auto-merge on promotion PRs.
- In `idklol-infra`:
  - `KUBECONFIG_B64`: base64-encoded kubeconfig used by Terraform plan/apply workflows.

Example to create the secret payload:

```bash
base64 -i ~/.kube/config | tr -d '\n'
```

### Workflows in this repo

- `.github/workflows/promote-server-images.yml`
  - Triggered by dispatch from `idklol-server`
  - Updates image variables in `prod.tfvars`
  - Opens a PR with immutable SHA tags

- `.github/workflows/promote-ue-image.yml`
  - Triggered by dispatch from `idklol-client` UE pipeline
  - Updates `ue_server_image` in `prod.tfvars`
  - Opens a PR with immutable SHA tags

- `.github/workflows/terraform-deploy.yml`
  - `pull_request`: fmt + validate + plan (when kubeconfig secret exists)
  - `push main`: apply + rollout health checks

## Hetzner Full Stack via Terraform

You can provision a budget single-node k3s cluster on Hetzner and deploy the full application stack using Terraform only.

1. Bootstrap k3s on Hetzner:

```bash
cd hetzner
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

2. Deploy the app stack from this repo root using the generated kubeconfig:

```bash
cd ..
terraform init
terraform apply -var-file=dev.tfvars -var "kubeconfig_path=$(terraform -chdir=hetzner output -raw kubeconfig_path)" -var "kube_context="
```

This flow uses:
- `hetzner/` root for infrastructure (VM + k3s + firewall)
- repo root for application layer (Helm releases + secrets + ingresses)

## k3s Notes

For a single VPS, `k3s` is the right default. It already gives you:

- a lightweight control plane
- an ingress controller by default via Traefik
- `LoadBalancer` support via ServiceLB for small environments

Use `ingress_class_name = "traefik"` unless you have replaced it with nginx.

## Keycloak Realm Import

The Terraform root includes the current realm definition under [assets/keycloak/realm-config.json](./assets/keycloak/realm-config.json). That file is mounted into the Bitnami Keycloak release and imported on startup.

The realm file templates these values at apply time:
- `__PUBLIC_WEB_URL__`
- `__KEYCLOAK_CHAT_CLIENT_SECRET__`
- `__KEYCLOAK_WEBADMIN_CLIENT_SECRET__`

This keeps initial Keycloak client secrets aligned with `prod.tfvars` and avoids bootstrap drift from hardcoded dev secrets.

The realm import no longer creates demo username/password accounts. Set `keycloak_admin_username` and `keycloak_admin_password` in your `.tfvars` file and rotate them by updating the values and re-running `terraform apply`.

## Limitations

- NATS is in-cluster by default because that is the most stable low-cost option.
- The NPC bridge is disabled by default; it expects an external Ollama-compatible endpoint.
- Terraform and Helm binaries are not installed in this workspace, so this scaffold was built statically and should be validated with `terraform init` and `terraform validate` on your machine.