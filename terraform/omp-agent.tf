resource "kubernetes_namespace" "sdlc" {
  metadata {
    name = "sdlc"
  }
}

resource "helm_release" "omp_agent" {
  name              = "omp-agent"
  chart             = "${path.module}/../helm/omp-agent"
  namespace         = kubernetes_namespace.sdlc.metadata[0].name
  dependency_update = true

  values = [file("${path.module}/../helm/omp-agent/values.yaml")]

  set {
    name  = "namespace"
    value = kubernetes_namespace.sdlc.metadata[0].name
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

  depends_on = [kubernetes_namespace.sdlc]
}
