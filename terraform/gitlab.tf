resource "kubernetes_namespace" "gitlab" {
  metadata {
    name = "gitlab"
  }
}

resource "kubernetes_secret" "gitlab_root_password" {
  metadata {
    name      = "gitlab-initial-root-password"
    namespace = kubernetes_namespace.gitlab.metadata[0].name
  }

  data = {
    password = var.gitlab_root_password
  }
}

resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  version    = "8.5.0"
  namespace  = kubernetes_namespace.gitlab.metadata[0].name
  timeout    = 600

  values = [file("${path.module}/../helm/gitlab/values.yaml")]

  set {
    name  = "gitlab.global.initialRootPassword.secret"
    value = kubernetes_secret.gitlab_root_password.metadata[0].name
  }

  set_sensitive {
    name  = "gitlab.postgresql.auth.password"
    value = var.gitlab_db_password
  }

  depends_on = [kubernetes_namespace.gitlab]
}
