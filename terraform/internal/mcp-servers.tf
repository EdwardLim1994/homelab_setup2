resource "kubernetes_namespace" "mcp_servers" {
  metadata {
    name = "mcp-servers"
  }
}

# ponytail: no maintained Taiga MCP image exists — same build+push pattern
# terraform/internal/taiga.tf/omp-agent.tf use for their own custom images.
resource "null_resource" "taiga_mcp_image" {
  triggers = {
    files = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/mcp-servers/taiga-mcp", "**") :
      filesha1("${path.module}/../../helm/mcp-servers/taiga-mcp/${f}")
    ]))
  }

  provisioner "local-exec" {
    working_dir = abspath("${path.module}/../../helm/mcp-servers/taiga-mcp")
    command      = "docker build -t localhost:5111/taiga-mcp:dev . && docker push localhost:5111/taiga-mcp:dev"
  }
}

resource "helm_release" "mcp_servers" {
  name              = "mcp-servers"
  chart             = "${path.module}/../../helm/mcp-servers"
  namespace         = kubernetes_namespace.mcp_servers.metadata[0].name
  dependency_update = true
  # ponytail: no boot-time discovery/health handshake in these servers (unlike
  # minio's OIDC discovery), but new/unverified — don't block apply on it.
  wait = false

  values = [file("${path.module}/../../helm/mcp-servers/values.yaml")]

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
    name  = "servers.n8n.env.AUTH_TOKEN"
    value = var.n8n_mcp_auth_token
  }

  set_sensitive {
    name  = "servers.taiga.env.TAIGA_TOKEN"
    value = var.taiga_api_token
  }

  # ponytail: in-cluster address, not local.app_url["taiga"] — same reasoning
  # as taiga.tf's own TAIGA_URL default (pods can't route to the tailnet VIP).
  set {
    name  = "servers.taiga.env.TAIGA_URL"
    value = "http://taiga-gateway.taiga.svc.cluster.local"
  }

  set_sensitive {
    name  = "servers.taiga.env.AUTH_TOKEN"
    value = var.taiga_mcp_auth_token
  }

  depends_on = [kubernetes_namespace.mcp_servers, null_resource.taiga_mcp_image]
}
