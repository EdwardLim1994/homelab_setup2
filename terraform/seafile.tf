resource "kubernetes_namespace" "seafile" {
  metadata {
    name = "seafile"
  }
}

resource "helm_release" "seafile" {
  name      = "seafile"
  chart     = "${path.module}/../helm/seafile"
  namespace = kubernetes_namespace.seafile.metadata[0].name
  timeout   = 600

  values = [file("${path.module}/../helm/seafile/values.yaml")]

  set_sensitive {
    name  = "seafile.env.DB_ROOT_PASSWD"
    value = var.seafile_db_root_password
  }

  set_sensitive {
    name  = "seafile.env.SEAFILE_ADMIN_PASSWORD"
    value = var.seafile_admin_password
  }

  set_sensitive {
    name  = "seafile.mariadb.auth.password"
    value = var.seafile_db_password
  }

  set_sensitive {
    name  = "seafile.mariadb.auth.rootPassword"
    value = var.seafile_db_root_password
  }

  depends_on = [kubernetes_namespace.seafile]
}
