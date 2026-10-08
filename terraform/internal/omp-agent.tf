resource "kubernetes_namespace" "sdlc" {
  metadata {
    name = "sdlc"
  }
}

# ponytail: omp-agent's Job image is the same image helm/omp's Dockerfile
# builds (omp + opencode + claude CLIs, every role's skill dir baked in) —
# reused rather than duplicated. Mirrors the build step that used to live in
# the now-deleted terraform/omp.tf.
resource "null_resource" "omp_agent_image" {
  triggers = {
    dockerfile = filesha1("${path.module}/../../helm/omp/Dockerfile")
    roles = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/omp/roles", "**") :
      filesha1("${path.module}/../../helm/omp/roles/${f}")
    ]))
    # ponytail: was missing entirely -- publish-pdf.sh/render-mermaid.sh
    # edits silently didn't trigger a rebuild without this, same class of
    # gap the roles/ hash above already covers for SKILL.md files.
    scripts = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/omp/scripts", "**") :
      filesha1("${path.module}/../../helm/omp/scripts/${f}")
    ]))
  }

  provisioner "local-exec" {
    working_dir = abspath("${path.module}/../../helm/omp")
    command     = "docker build -t localhost:5111/omp-box:dev . && docker push localhost:5111/omp-box:dev"
  }
}

# ponytail: devops-engineer role's F-02 kickoff step needs to get/apply
# ArgoCD Applications it just built (helm chart + env values scaffolding) --
# omp-agent's own Role (helm/omp-agent/templates/role.yaml) is namespace-
# scoped to sdlc only, so this needs a second Role+RoleBinding in argocd
# itself, same cross-namespace shape as ansible.tf's ansible_gitlab_exec /
# ansible_argocd_clusters. Found via a live Job run reporting Forbidden on
# every `kubectl get/apply application.argoproj.io -n argocd` attempt.
resource "kubernetes_role" "omp_agent_argocd" {
  metadata {
    name      = "omp-agent-argocd"
    namespace = "argocd"
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications"]
    verbs      = ["get", "list", "create", "patch"]
  }
  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_role_binding" "omp_agent_argocd" {
  metadata {
    name      = "omp-agent-argocd"
    namespace = "argocd"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.omp_agent_argocd.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "omp-agent"
    namespace = kubernetes_namespace.sdlc.metadata[0].name
  }
}

resource "helm_release" "omp_agent" {
  name              = "omp-agent"
  chart             = "${path.module}/../../helm/omp-agent"
  namespace         = kubernetes_namespace.sdlc.metadata[0].name
  dependency_update = true

  values = [file("${path.module}/../../helm/omp-agent/values.yaml")]

  set {
    name  = "namespace"
    value = kubernetes_namespace.sdlc.metadata[0].name
  }

  # ponytail: the helm provider doesn't hash local chart files, so a
  # template-only edit (e.g. role.yaml's RBAC rules) wouldn't trigger a
  # helm upgrade on its own — same gotcha ansible.tf/mermaid-render.tf work
  # around.
  set {
    name = "chartHash"
    value = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/omp-agent", "**") :
      filesha1("${path.module}/../../helm/omp-agent/${f}")
    ]))
  }

  # reuse existing tokens — see terraform/variables.tf
  set_sensitive {
    name  = "secrets.gitlabToken"
    value = var.omp_gitlab_token
  }

  set_sensitive {
    name  = "secrets.claudeCodeToken"
    value = var.claude_code_token
  }

  set_sensitive {
    name  = "secrets.gitlabRepoUrl"
    value = var.omp_gitlab_repo_url
  }

  set_sensitive {
    name  = "secrets.kaneoToken"
    value = var.kaneo_api_token
  }

  # ponytail: in-cluster address, not local.app_url["kaneo"] (external
  # tailnet URL) — agent pods can't route to the Tailscale Service VIP any
  # more than n8n can (see AGENT.md's "in-cluster can't reach the tailnet
  # hostname"). Matches helm/kaneo/values.yaml's own server-side convention.
  set {
    name  = "secrets.kaneoUrl"
    value = "http://kaneo.kaneo.svc.cluster.local:5173"
  }

  # ponytail: unlike kaneoUrl above, this one IS the external tailnet URL —
  # it's for a human reviewer to click from an MR description (browser
  # traffic), not an in-cluster API call.
  set {
    name  = "secrets.grafanaUrl"
    value = local.app_url["grafana"]
  }

  set_sensitive {
    name  = "secrets.sonarqubeMcpAuthToken"
    value = var.sonarqube_mcp_token
  }

  # ponytail: in-cluster address, admin login reused (same account
  # terraform/internal/nextcloud.tf sets nextcloud.nextcloud.password with) —
  # no separate robot account, homelab-scoped like Harbor's admin reuse.
  set {
    name  = "secrets.nextcloudUrl"
    value = "http://nextcloud.nextcloud.svc.cluster.local:8080"
  }

  set {
    name  = "secrets.nextcloudUser"
    value = "admin"
  }

  set_sensitive {
    name  = "secrets.nextcloudPassword"
    value = var.nextcloud_admin_password
  }

  # ponytail: closes a pre-existing gap — F-01/F-02 prompts already reference
  # $MINIO_ENDPOINT/$MINIO_ROOT_USER/$MINIO_ROOT_PASSWORD for `mc alias set`,
  # but no Job env ever supplied them. Same admin account minio.tf's own
  # lifecycle-rule provisioner uses.
  set {
    name  = "secrets.minioEndpoint"
    value = "http://minio.minio.svc.cluster.local:9000"
  }

  set {
    name  = "secrets.minioRootUser"
    value = "admin"
  }

  set_sensitive {
    name  = "secrets.minioRootPassword"
    value = var.minio_root_password
  }

  depends_on = [kubernetes_namespace.sdlc, null_resource.omp_agent_image, null_resource.kaneo_mcp_image]
}
