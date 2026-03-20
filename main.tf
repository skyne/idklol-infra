terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}

locals {
  keycloak_realm_name       = "idklol"
  public_scheme             = var.ingress_tls_enabled ? "https" : "http"
  keycloak_public_base_url  = "${local.public_scheme}://${var.keycloak_host}"
  keycloak_public_realm     = "${local.keycloak_public_base_url}/realms/${local.keycloak_realm_name}"
  keycloak_internal_base    = "http://keycloak.${var.namespace}.svc.cluster.local"
  keycloak_internal_realm   = "${local.keycloak_internal_base}/realms/${local.keycloak_realm_name}"
  webadmin_public_url       = "${local.public_scheme}://${var.webadmin_host}"
  otlp_endpoint             = var.otlp_endpoint != null ? trimspace(var.otlp_endpoint) : ""
  otlp_headers              = var.otlp_auth_header != null ? trimspace(var.otlp_auth_header) : ""
  external_nats_url         = var.external_nats_url != null ? trimspace(var.external_nats_url) : ""
  tracing_enabled           = local.otlp_endpoint != ""
  use_external_nats         = local.external_nats_url != ""
  deploy_nats               = !local.use_external_nats && var.deploy_incluster_nats
  nats_url                  = local.use_external_nats ? local.external_nats_url : "nats://nats.${var.namespace}.svc.cluster.local:4222"
  postgres_suffix           = var.external_postgres_sslmode == "" ? "" : "?sslmode=${var.external_postgres_sslmode}"
  characters_database_url   = "postgresql://${urlencode(var.external_postgres_username)}:${urlencode(var.external_postgres_password)}@${var.external_postgres_host}:${var.external_postgres_port}/${var.characters_database_name}${local.postgres_suffix}"
  npc_metadata_database_url = "postgresql://${urlencode(var.external_postgres_username)}:${urlencode(var.external_postgres_password)}@${var.external_postgres_host}:${var.external_postgres_port}/${var.npc_metadata_database_name}${local.postgres_suffix}"
  cluster_issuer_name_clean = try(trimspace(var.cluster_issuer_name), "")
  cert_manager_annotations = local.cluster_issuer_name_clean != "" ? {
    "cert-manager.io/cluster-issuer" = local.cluster_issuer_name_clean
  } : {}
  grpc_ingress_annotations = var.ingress_class_name == "nginx" ? merge(local.cert_manager_annotations, {
    "nginx.ingress.kubernetes.io/backend-protocol" = "GRPC"
    }) : var.ingress_class_name == "traefik" ? merge(local.cert_manager_annotations, {
    "traefik.ingress.kubernetes.io/service.serversscheme" = "h2c"
  }) : local.cert_manager_annotations
}

resource "kubernetes_namespace_v1" "stack" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "idklol"
      "app.kubernetes.io/part-of"    = "idklol-server"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret_v1" "platform_shared" {
  metadata {
    name      = "idklol-shared-secrets"
    namespace = kubernetes_namespace_v1.stack.metadata[0].name
  }

  data = {
    "postgres-username"               = var.external_postgres_username
    "postgres-password"               = var.external_postgres_password
    "characters-database-url"         = local.characters_database_url
    "npc-metadata-database-url"       = local.npc_metadata_database_url
    "keycloak-admin-password"         = var.keycloak_admin_password
    "keycloak-chat-client-secret"     = var.keycloak_chat_client_secret
    "keycloak-webadmin-client-secret" = var.keycloak_webadmin_client_secret
    "nextauth-secret"                 = var.nextauth_secret
  }

  type = "Opaque"
}

resource "kubernetes_config_map_v1" "keycloak_realm" {
  metadata {
    name      = "keycloak-realm-import"
    namespace = kubernetes_namespace_v1.stack.metadata[0].name
  }

  data = {
    "realm-config.json" = replace(
      replace(
        replace(
          file("${path.module}/assets/keycloak/realm-config.json"),
          "__PUBLIC_WEB_URL__",
          local.webadmin_public_url,
        ),
        "__KEYCLOAK_CHAT_CLIENT_SECRET__",
        var.keycloak_chat_client_secret,
      ),
      "__KEYCLOAK_WEBADMIN_CLIENT_SECRET__",
      var.keycloak_webadmin_client_secret,
    )
  }
}

resource "helm_release" "nats" {
  count = local.deploy_nats ? 1 : 0

  name             = "nats"
  namespace        = kubernetes_namespace_v1.stack.metadata[0].name
  create_namespace = false
  repository       = "https://nats-io.github.io/k8s/helm/charts/"
  chart            = "nats"
  version          = "2.12.5"

  values = [
    yamlencode({
      config = {
        cluster = {
          enabled  = false
          replicas = 1
        }
        jetstream = {
          enabled = true
          fileStore = {
            enabled = true
            pvc = {
              enabled = true
              size    = "8Gi"
            }
          }
        }
      }
      service = {
        merge = {
          spec = {
            type = "ClusterIP"
          }
        }
      }
      container = {
        merge = {
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
      promExporter = {
        enabled = false
      }
      natsBox = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.stack]
}

resource "helm_release" "keycloak" {
  name             = "keycloak"
  namespace        = kubernetes_namespace_v1.stack.metadata[0].name
  create_namespace = false
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "keycloak"
  version          = "25.2.0"
  timeout          = 900

  values = [
    yamlencode({
      image = {
        registry   = "docker.io"
        repository = "bitnamilegacy/keycloak"
        tag        = "26.3.3-debian-12-r0"
      }
      auth = {
        adminUser         = var.keycloak_admin_username
        existingSecret    = kubernetes_secret_v1.platform_shared.metadata[0].name
        passwordSecretKey = "keycloak-admin-password"
      }
      production   = false
      httpEnabled  = true
      proxyHeaders = "xforwarded"
      logging = {
        level  = "INFO"
        output = "default"
      }
      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1500m"
          memory = "2Gi"
        }
      }
      postgresql = {
        enabled = false
      }
      externalDatabase = {
        host                      = var.external_postgres_host
        port                      = var.external_postgres_port
        database                  = var.keycloak_database_name
        existingSecret            = kubernetes_secret_v1.platform_shared.metadata[0].name
        existingSecretUserKey     = "postgres-username"
        existingSecretPasswordKey = "postgres-password"
      }
      ingress = {
        enabled          = true
        ingressClassName = var.ingress_class_name
        hostname         = var.keycloak_host
        annotations      = local.cert_manager_annotations
        tls              = var.ingress_tls_enabled
      }
      extraStartupArgs = "--import-realm"
      extraVolumes = [
        {
          name = "realm-import"
          configMap = {
            name = kubernetes_config_map_v1.keycloak_realm.metadata[0].name
          }
        }
      ]
      extraVolumeMounts = [
        {
          name      = "realm-import"
          mountPath = "/opt/bitnami/keycloak/data/import"
          readOnly  = true
        }
      ]
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.stack,
    kubernetes_secret_v1.platform_shared,
    kubernetes_config_map_v1.keycloak_realm,
  ]
}

resource "helm_release" "app_stack" {
  name             = "idklol-stack"
  namespace        = kubernetes_namespace_v1.stack.metadata[0].name
  create_namespace = false
  chart            = "${path.module}/helm/idklol-stack"

  values = [
    yamlencode({
      global = {
        sharedSecretName = kubernetes_secret_v1.platform_shared.metadata[0].name
        imagePullSecrets = var.image_pull_secret_names
      }
      services = {
        chatserver = {
          enabled      = true
          image        = var.chatserver_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
          env = {
            KEYCLOAK_URL                = local.keycloak_internal_realm
            KEYCLOAK_CLIENT_ID          = "idklol-chat"
            LOG_LEVEL                   = "info"
            LOG_OUTPUT                  = "console"
            LOG_FORMAT                  = "plain"
            TRACING_OTLP_ENABLED        = local.tracing_enabled ? "true" : "false"
            OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
            OTEL_EXPORTER_OTLP_HEADERS  = local.otlp_headers
            TRACING_SAMPLE_RATIO        = "1.0"
          }
          secretEnv = {
            KEYCLOAK_CLIENT_SECRET = "keycloak-chat-client-secret"
          }
          waitFor = [
            {
              host = "keycloak.${var.namespace}.svc.cluster.local"
              port = 80
            }
          ]
          probes = {
            enabled       = true
            tcpSocketPort = 50052
          }
          containerPorts = [
            {
              name          = "grpc"
              containerPort = 50052
              protocol      = "TCP"
            }
          ]
          service = {
            enabled = true
            type    = "ClusterIP"
            ports = [
              {
                name       = "grpc"
                port       = 50052
                targetPort = "grpc"
                protocol   = "TCP"
              }
            ]
          }
          ingress = {
            enabled         = true
            className       = var.ingress_class_name
            annotations     = local.grpc_ingress_annotations
            host            = var.chat_grpc_host
            path            = "/"
            pathType        = "Prefix"
            tlsEnabled      = var.ingress_tls_enabled
            tlsSecretName   = "chat-grpc-tls"
            servicePortName = "grpc"
          }
        }
        "characters-grpc" = {
          enabled      = true
          image        = var.characters_grpc_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "700m"
              memory = "768Mi"
            }
          }
          env = {
            KEYCLOAK_URL                = local.keycloak_internal_realm
            KEYCLOAK_CLIENT_ID          = "idklol-chat"
            LOG_LEVEL                   = "info"
            LOG_OUTPUT                  = "console"
            LOG_FORMAT                  = "plain"
            TRACING_OTLP_ENABLED        = local.tracing_enabled ? "true" : "false"
            OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
            OTEL_EXPORTER_OTLP_HEADERS  = local.otlp_headers
            TRACING_SAMPLE_RATIO        = "1.0"
          }
          secretEnv = {
            DATABASE_URL           = "characters-database-url"
            KEYCLOAK_CLIENT_SECRET = "keycloak-chat-client-secret"
          }
          waitFor = [
            {
              host = "keycloak.${var.namespace}.svc.cluster.local"
              port = 80
            }
          ]
          probes = {
            enabled       = true
            tcpSocketPort = 50052
          }
          containerPorts = [
            {
              name          = "grpc"
              containerPort = 50052
              protocol      = "TCP"
            }
          ]
          service = {
            enabled = true
            type    = "ClusterIP"
            ports = [
              {
                name       = "grpc"
                port       = 50052
                targetPort = "grpc"
                protocol   = "TCP"
              }
            ]
          }
          ingress = {
            enabled         = true
            className       = var.ingress_class_name
            annotations     = local.grpc_ingress_annotations
            host            = var.characters_grpc_host
            path            = "/"
            pathType        = "Prefix"
            tlsEnabled      = var.ingress_tls_enabled
            tlsSecretName   = "characters-grpc-tls"
            servicePortName = "grpc"
          }
        }
        "characters-admin" = {
          enabled      = true
          image        = var.characters_admin_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "400m"
              memory = "384Mi"
            }
          }
          env = {
            KEYCLOAK_URL                = local.keycloak_internal_realm
            KEYCLOAK_CLIENT_ID          = "idklol-webadmin"
            NATS_URL                    = local.nats_url
            LOG_LEVEL                   = "info"
            LOG_OUTPUT                  = "console"
            LOG_FORMAT                  = "plain"
            TRACING_OTLP_ENABLED        = local.tracing_enabled ? "true" : "false"
            OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
            OTEL_EXPORTER_OTLP_HEADERS  = local.otlp_headers
            TRACING_SAMPLE_RATIO        = "1.0"
          }
          secretEnv = {
            DATABASE_URL           = "characters-database-url"
            KEYCLOAK_CLIENT_SECRET = "keycloak-webadmin-client-secret"
          }
          waitFor = concat(
            [
              {
                host = "keycloak.${var.namespace}.svc.cluster.local"
                port = 80
              }
            ],
            local.deploy_nats ? [
              {
                host = "nats.${var.namespace}.svc.cluster.local"
                port = 4222
              }
            ] : []
          )
          service = {
            enabled = false
          }
        }
        "characters-server" = {
          enabled      = true
          image        = var.characters_server_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "150m"
              memory = "192Mi"
            }
            limits = {
              cpu    = "600m"
              memory = "512Mi"
            }
          }
          env = {
            NATS_URL                    = local.nats_url
            LOG_LEVEL                   = "info"
            LOG_OUTPUT                  = "console"
            LOG_FORMAT                  = "plain"
            TRACING_OTLP_ENABLED        = local.tracing_enabled ? "true" : "false"
            OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
            OTEL_EXPORTER_OTLP_HEADERS  = local.otlp_headers
            TRACING_SAMPLE_RATIO        = "1.0"
          }
          secretEnv = {
            DATABASE_URL = "characters-database-url"
          }
          waitFor = local.deploy_nats ? [
            {
              host = "nats.${var.namespace}.svc.cluster.local"
              port = 4222
            }
          ] : []
          service = {
            enabled = false
          }
        }
        "npc-metadata-service" = {
          enabled      = true
          image        = var.npc_metadata_service_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "400m"
              memory = "384Mi"
            }
          }
          env = {
            NATS_URL                    = local.nats_url
            LOG_LEVEL                   = "info"
            LOG_OUTPUT                  = "console"
            LOG_FORMAT                  = "plain"
            TRACING_OTLP_ENABLED        = local.tracing_enabled ? "true" : "false"
            OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
            OTEL_EXPORTER_OTLP_HEADERS  = local.otlp_headers
            TRACING_SAMPLE_RATIO        = "1.0"
          }
          secretEnv = {
            DATABASE_URL = "npc-metadata-database-url"
          }
          waitFor = local.deploy_nats ? [
            {
              host = "nats.${var.namespace}.svc.cluster.local"
              port = 4222
            }
          ] : []
          service = {
            enabled = false
          }
        }
        webadmin = {
          enabled      = true
          image        = var.webadmin_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "400m"
              memory = "384Mi"
            }
          }
          env = {
            NODE_ENV                     = "production"
            HOSTNAME                     = "0.0.0.0"
            AUTH_DEBUG                   = "false"
            AUTH_TRUST_HOST              = "true"
            AUTH_URL                     = local.webadmin_public_url
            NEXTAUTH_URL                 = local.webadmin_public_url
            KEYCLOAK_ID                  = "idklol-webadmin"
            KEYCLOAK_ISSUER              = "https://${var.keycloak_host}/realms/${local.keycloak_realm_name}"
            KEYCLOAK_EXTERNAL_ISSUER     = "https://${var.keycloak_host}/realms/${local.keycloak_realm_name}"
            NODE_TLS_REJECT_UNAUTHORIZED = "0"
            NATS_URL                     = local.nats_url
            TRACING_OTLP_ENABLED         = local.tracing_enabled ? "true" : "false"
            OTEL_EXPORTER_OTLP_ENDPOINT  = local.otlp_endpoint
            OTEL_EXPORTER_OTLP_HEADERS   = local.otlp_headers
            TRACING_SAMPLE_RATIO         = "1.0"
          }
          secretEnv = {
            NEXTAUTH_SECRET = "nextauth-secret"
            KEYCLOAK_SECRET = "keycloak-webadmin-client-secret"
          }
          waitFor = concat(
            [
              {
                host = "keycloak.${var.namespace}.svc.cluster.local"
                port = 80
              }
            ],
            local.deploy_nats ? [
              {
                host = "nats.${var.namespace}.svc.cluster.local"
                port = 4222
              }
            ] : []
          )
          probes = {
            enabled       = true
            tcpSocketPort = 3001
          }
          containerPorts = [
            {
              name          = "https-proxy"
              containerPort = 3000
              protocol      = "TCP"
            },
            {
              name          = "http"
              containerPort = 3001
              protocol      = "TCP"
            }
          ]
          service = {
            enabled = true
            type    = "ClusterIP"
            ports = [
              {
                name       = "http"
                port       = 3000
                targetPort = "http"
                protocol   = "TCP"
              }
            ]
          }
          ingress = {
            enabled         = true
            className       = var.ingress_class_name
            annotations     = local.cert_manager_annotations
            host            = var.webadmin_host
            path            = "/"
            pathType        = "Prefix"
            tlsEnabled      = var.ingress_tls_enabled
            tlsSecretName   = "webadmin-tls"
            servicePortName = "http"
          }
        }
        "ue-server" = {
          enabled      = true
          image        = var.ue_server_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2500m"
              memory = "4Gi"
            }
          }
          env = {
            MAP_PATH    = var.ue_server_map_path
            GAME_PORT   = "7777"
            NATS_URL    = local.nats_url
            INSTANCE_ID = "server-1"
            LOG_LEVEL   = "Log"
          }
          waitFor = local.deploy_nats ? [
            {
              host = "nats.${var.namespace}.svc.cluster.local"
              port = 4222
            }
          ] : []
          containerPorts = [
            {
              name          = "game"
              containerPort = 7777
              protocol      = "UDP"
            },
            {
              name          = "beacon"
              containerPort = 7787
              protocol      = "UDP"
            }
          ]
          service = {
            enabled = true
            type    = var.ue_server_service_type
            ports = [
              {
                name       = "game"
                port       = 7777
                targetPort = "game"
                protocol   = "UDP"
              },
              {
                name       = "beacon"
                port       = 7787
                targetPort = "beacon"
                protocol   = "UDP"
              }
            ]
          }
        }
        "npc-interactions-bridge" = {
          enabled      = var.deploy_npc_interactions_bridge
          image        = var.npc_interactions_bridge_image
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
          env = {
            NATS_URL                    = local.nats_url
            OLLAMA_BASE_URL             = var.ollama_base_url
            OLLAMA_MODEL                = var.ollama_model
            NPC_BRIDGE_REQUEST_SUBJECT  = "npc.interactions.request"
            NPC_BRIDGE_RESPONSE_SUBJECT = "npc.interactions.response"
            NPC_BRIDGE_PROMPTS_DIR      = "/srv/prompts"
            NPC_BRIDGE_DEFAULT_PROMPT   = "default/system"
            LOG_LEVEL                   = "info"
            LOG_OUTPUT                  = "console"
            LOG_FORMAT                  = "plain"
            TRACING_OTLP_ENABLED        = local.tracing_enabled ? "true" : "false"
            OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
            OTEL_EXPORTER_OTLP_HEADERS  = local.otlp_headers
            TRACING_SAMPLE_RATIO        = "1.0"
          }
          waitFor = local.deploy_nats ? [
            {
              host = "nats.${var.namespace}.svc.cluster.local"
              port = 4222
            }
          ] : []
          service = {
            enabled = false
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.stack,
    kubernetes_secret_v1.platform_shared,
    helm_release.keycloak,
  ]
}