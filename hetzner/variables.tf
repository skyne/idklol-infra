variable "hcloud_token" {
  description = "Hetzner Cloud API token."
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the Hetzner server and logical k3s cluster."
  type        = string
  default     = "idklol-k3s"
}

variable "location" {
  description = "Hetzner location (e.g. fsn1, nbg1, hel1)."
  type        = string
  default     = "fsn1"
}

variable "server_type" {
  description = "Hetzner server type. cx33 (4 vCPU / 8 GB RAM / 80 GB, ~€6.34/mo) is a good baseline when Postgres is on a free-tier SaaS (Neon) — only NATS + app services run on the node. Use cx43 if you need more headroom for the UE server."
  type        = string
  default     = "cx33"
}

variable "image" {
  description = "Server image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "enable_ipv6" {
  description = "Enable public IPv6 on the server."
  type        = bool
  default     = true
}

variable "k3s_version" {
  description = "Optional pinned k3s version. Empty string means latest stable."
  type        = string
  default     = ""
}

variable "disable_traefik" {
  description = "Disable Traefik in k3s. Keep false unless you install another ingress controller."
  type        = bool
  default     = false
}

variable "k3s_write_kubeconfig_mode" {
  description = "k3s kubeconfig file mode written on the server."
  type        = string
  default     = "644"
}

variable "ssh_key_name" {
  description = "Name for the uploaded Hetzner SSH key resource."
  type        = string
  default     = "idklol-k3s-key"
}

variable "create_ssh_key" {
  description = "Set to false if the SSH key named ssh_key_name already exists in your Hetzner project and you want to reuse it instead of creating a new one."
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "SSH public key contents to authorize on the server."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Local path to the matching private SSH key used to fetch kubeconfig."
  type        = string
}

variable "ssh_user" {
  description = "SSH user for cloud image access."
  type        = string
  default     = "root"
}

variable "local_kubeconfig_path" {
  description = "Local file path where Terraform should write the fetched kubeconfig."
  type        = string
  default     = "./generated/kubeconfig.yaml"
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH into the cluster node."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "kube_api_allowed_cidrs" {
  description = "CIDRs allowed to access Kubernetes API on 6443."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "public_ingress_allowed_cidrs" {
  description = "CIDRs allowed to access HTTP/HTTPS and UE UDP ports."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}