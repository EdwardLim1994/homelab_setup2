resource "kubernetes_namespace" "mcp_servers" {
  metadata {
    name = "mcp-servers"
  }
}

# ponytail: Kaneo's own native MCP endpoint expects an OAuth-resolvable
# bearer with dynamic client registration — built for interactive clients,
# awkward for a static per-role bearer in a batch Job. Mirror taiga-mcp's
# hand-rolled shape instead (same build+push pattern as every other custom
# image in this repo) — 4 generic REST tools against Kaneo's plain REST API.
resource "null_resource" "kaneo_mcp_image" {
  triggers = {
    files = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/mcp-servers/kaneo-mcp", "**") :
      filesha1("${path.module}/../../helm/mcp-servers/kaneo-mcp/${f}")
    ]))
  }

  provisioner "local-exec" {
    working_dir = abspath("${path.module}/../../helm/mcp-servers/kaneo-mcp")
    command      = "docker build -t localhost:5111/kaneo-mcp:dev . && docker push localhost:5111/kaneo-mcp:dev"
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

  # ponytail: in-cluster address, not local.app_url["kaneo"] — same reasoning
  # as kaneo.tf's own server-side OIDC endpoints (pods can't route to the
  # tailnet VIP, see AGENT.md's "in-cluster can't reach the tailnet hostname").
  # No static KANEO_TOKEN/AUTH_TOKEN here — kaneo-mcp forwards whatever
  # bearer the caller sends straight through to Kaneo's API (see its own
  # ponytail comment), so each role's real per-role API key is the auth.
  set {
    name  = "servers.kaneo.env.KANEO_URL"
    value = "http://kaneo.kaneo.svc.cluster.local:5173"
  }

  depends_on = [kubernetes_namespace.mcp_servers, null_resource.kaneo_mcp_image]
}
