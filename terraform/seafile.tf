resource "kubernetes_namespace" "seafile" {
  metadata {
    name = "seafile"
  }
}

# ponytail: seafile 13.x hard-requires redis for seahub's cache backend (no
# opt-out). Bare redis Deployment, not a subchart — matches Tiltfile.
# Service is named "seafile-redis", NOT "redis" — Kubernetes auto-injects
# Docker-links-style "REDIS_PORT=tcp://..." env vars into every pod in the
# namespace named after a Service called "redis", which collides with and
# overrides seahub's own REDIS_PORT config lookup.
resource "kubernetes_deployment" "seafile_redis" {
  metadata {
    name      = "seafile-redis"
    namespace = kubernetes_namespace.seafile.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "seafile-redis" }
    }
    template {
      metadata {
        labels = { app = "seafile-redis" }
      }
      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"
          port {
            container_port = 6379
          }
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.seafile]
}

resource "kubernetes_service" "seafile_redis" {
  metadata {
    name      = "seafile-redis"
    namespace = kubernetes_namespace.seafile.metadata[0].name
  }
  spec {
    selector = { app = "seafile-redis" }
    port {
      port = 6379
    }
  }
  depends_on = [kubernetes_namespace.seafile]
}

resource "helm_release" "seafile" {
  name      = "seafile"
  chart     = "${path.module}/../helm/seafile"
  namespace = kubernetes_namespace.seafile.metadata[0].name
  timeout   = 600

  # ponytail: postStart script's OAuth config is one big multi-line shell
  # string (see values.yaml comment) — placeholder substitution on the
  # rendered file, not --set, matches the Tiltfile's own approach.
  values = [
    replace(
      replace(
        replace(file("${path.module}/../helm/seafile/values.yaml"), "__TS_HOST__", var.ts_host),
        "__SEAFILE_OIDC_CLIENT_ID__", var.seafile_oidc_client_id
      ),
      "__SEAFILE_OIDC_CLIENT_SECRET__", var.seafile_oidc_client_secret
    )
  ]

  # ponytail: image 13.0.25 renamed all the chart's default (pre-9.x) env
  # keys — INIT_SEAFILE_MYSQL_ROOT_PASSWORD / INIT_SEAFILE_ADMIN_PASSWORD,
  # not DB_ROOT_PASSWD / SEAFILE_ADMIN_PASSWORD. The old names silently
  # no-op and bootstrap hangs forever waiting on mysql/admin creation.
  set_sensitive {
    name  = "seafile.env.INIT_SEAFILE_MYSQL_ROOT_PASSWORD"
    value = var.seafile_db_root_password
  }

  set_sensitive {
    name  = "seafile.env.INIT_SEAFILE_ADMIN_PASSWORD"
    value = var.seafile_admin_password
  }

  set_sensitive {
    name  = "seafile.env.SEAFILE_MYSQL_DB_PASSWORD"
    value = var.seafile_db_password
  }

  set_sensitive {
    name  = "seafile.env.JWT_PRIVATE_KEY"
    value = var.seafile_jwt_private_key
  }

  set_sensitive {
    name  = "seafile.mariadb.auth.password"
    value = var.seafile_db_password
  }

  set_sensitive {
    name  = "seafile.mariadb.auth.rootPassword"
    value = var.seafile_db_root_password
  }

  depends_on = [kubernetes_namespace.seafile, kubernetes_service.seafile_redis]
}

# ponytail: mirrors Tiltfile's seafile-promote-admin — no-op until
# ADMIN_EMAIL has logged in via SSO at least once (JIT-creates the
# account), safe to re-run any time.
resource "null_resource" "seafile_promote_admin" {
  triggers = {
    admin_email = var.admin_email
    script_hash = filesha1("${path.module}/../helm/seafile/promote-admin.sh")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "bash '${local_file.seafile_promote_admin_script.filename}'"
  }

  depends_on = [helm_release.seafile, local_file.seafile_promote_admin_script]
}

resource "local_file" "seafile_promote_admin_script" {
  filename = "${path.module}/.seafile-promote-admin.sh"
  content = join("\n", [
    "kubectl exec -i -n seafile deploy/seafile -- env ADMIN_EMAIL='${var.admin_email}' bash < '${abspath(path.module)}/../helm/seafile/promote-admin.sh'",
    "",
  ])
}
