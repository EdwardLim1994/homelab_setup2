resource "kubernetes_namespace" "mcp_servers" {
  metadata {
    name = "mcp-servers"
  }
}

resource "helm_release" "mcp_servers" {
  name              = "mcp-servers"
  chart             = "${path.module}/../helm/mcp-servers"
  namespace         = kubernetes_namespace.mcp_servers.metadata[0].name
  dependency_update = true
  # ponytail: no boot-time discovery/health handshake in these servers (unlike
  # minio's OIDC discovery), but new/unverified — don't block apply on it.
  wait = false

  values = [file("${path.module}/../helm/mcp-servers/values.yaml")]

  set_sensitive {
    name  = "servers.grafana.env.GRAFANA_SERVICE_ACCOUNT_TOKEN"
    value = var.grafana_mcp_token
  }

  set_sensitive {
    name  = "servers.sonarqube.env.SONARQUBE_TOKEN"
    value = var.sonarqube_mcp_token
  }

  set_sensitive {
    name  = "servers.gitlab.env.GITLAB_PERSONAL_ACCESS_TOKEN"
    value = var.gitlab_mcp_token
  }

  set_sensitive {
    name  = "servers.gitlab.env.STREAMABLE_HTTP_AUTH_TOKEN"
    value = var.gitlab_mcp_auth_token
  }

  set_sensitive {
    name  = "servers.nx.env.NX_CLOUD_ACCESS_TOKEN"
    value = var.nx_cloud_mcp_token
  }

  depends_on = [kubernetes_namespace.mcp_servers]
}
