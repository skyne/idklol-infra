terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.52"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

locals {
  kubeconfig_output_path = abspath(var.local_kubeconfig_path)
  # Resolve SSH key ID: prefer the existing key if create_ssh_key = false,
  # otherwise use the newly created one.
  ssh_key_id = var.create_ssh_key ? hcloud_ssh_key.k3s[0].id : data.hcloud_ssh_key.existing[0].id
}

# Look up an existing Hetzner SSH key by name (used when create_ssh_key = false).
data "hcloud_ssh_key" "existing" {
  count = var.create_ssh_key ? 0 : 1
  name  = var.ssh_key_name
}

resource "hcloud_ssh_key" "k3s" {
  count      = var.create_ssh_key ? 1 : 0
  name       = var.ssh_key_name
  public_key = var.ssh_public_key
}

resource "hcloud_firewall" "k3s" {
  name = "${var.cluster_name}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = var.kube_api_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = var.public_ingress_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = var.public_ingress_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "7777"
    source_ips = var.public_ingress_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "7787"
    source_ips = var.public_ingress_allowed_cidrs
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "k3s" {
  name        = var.cluster_name
  server_type = var.server_type
  image       = var.image
  location    = var.location

  ssh_keys = [local.ssh_key_id]
  user_data = templatefile("${path.module}/cloud-init/k3s-server.yaml.tftpl", {
    k3s_version      = var.k3s_version
    node_name        = var.cluster_name
    disable_traefik  = var.disable_traefik
    write_kubeconfig = var.k3s_write_kubeconfig_mode
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = var.enable_ipv6
  }

  firewall_ids = [hcloud_firewall.k3s.id]
}

resource "null_resource" "fetch_kubeconfig" {
  triggers = {
    server_id    = hcloud_server.k3s.id
    server_ip    = hcloud_server.k3s.ipv4_address
    output_path  = local.kubeconfig_output_path
    private_key  = pathexpand(var.ssh_private_key_path)
    ssh_username = var.ssh_user
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      mkdir -p "$(dirname "${local.kubeconfig_output_path}")"

      SSH_KEY="${pathexpand(var.ssh_private_key_path)}"
      SSH_USER="${var.ssh_user}"
      SSH_HOST="${hcloud_server.k3s.ipv4_address}"

      ssh_cmd() {
        ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=5 \
            -i "$SSH_KEY" \
            "$SSH_USER@$SSH_HOST" "$@"
      }

      # Wait for SSH daemon to become reachable first.
      ssh_ready=0
      for i in $(seq 1 120); do
        if ssh_cmd true >/dev/null 2>&1; then
          ssh_ready=1
          break
        fi
        echo "waiting for SSH..."
        sleep 5
      done

      if [ "$ssh_ready" -ne 1 ]; then
        echo "Timed out waiting for SSH on $SSH_HOST after 10 minutes." >&2
        exit 1
      fi

      # Wait up to 30 minutes for k3s to install and write kubeconfig.
      ready=0
      for i in $(seq 1 180); do
        if ssh_cmd 'sudo test -f /etc/rancher/k3s/k3s.yaml' >/dev/null 2>&1; then
          ready=1
          break
        fi

        # Fail fast if k3s service has entered failed state.
        if ssh_cmd 'sudo systemctl is-failed --quiet k3s' >/dev/null 2>&1; then
          echo "k3s service failed during bootstrap; recent logs:" >&2
          ssh_cmd 'sudo journalctl -u k3s --no-pager -n 120 || true' >&2 || true
          ssh_cmd 'sudo cloud-init status || true' >&2 || true
          ssh_cmd 'sudo tail -n 120 /var/log/cloud-init-output.log || true' >&2 || true
          exit 1
        fi

        echo "waiting for k3s kubeconfig..."
        sleep 10
      done

      if [ "$ready" -ne 1 ]; then
        echo "Timed out waiting for /etc/rancher/k3s/k3s.yaml after 30 minutes." >&2
        echo "Diagnostics:" >&2
        ssh_cmd 'sudo cloud-init status || true' >&2 || true
        ssh_cmd 'sudo systemctl status k3s --no-pager -l || true' >&2 || true
        ssh_cmd 'sudo journalctl -u k3s --no-pager -n 120 || true' >&2 || true
        ssh_cmd 'sudo tail -n 120 /var/log/cloud-init-output.log || true' >&2 || true
        exit 1
      fi

      ssh_cmd 'sudo cat /etc/rancher/k3s/k3s.yaml' > "${local.kubeconfig_output_path}"
      sed -i.bak "s/127.0.0.1/${hcloud_server.k3s.ipv4_address}/g" "${local.kubeconfig_output_path}"
      rm -f "${local.kubeconfig_output_path}.bak"
      chmod 600 "${local.kubeconfig_output_path}"
    EOT
  }

  depends_on = [hcloud_server.k3s]
}