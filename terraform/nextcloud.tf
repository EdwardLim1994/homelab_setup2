resource "kubernetes_namespace" "nextcloud" {
  metadata {
    name = "nextcloud"
  }
}

resource "helm_release" "nextcloud" {
  name      = "nextcloud"
  chart     = "${path.module}/../helm/nextcloud"
  namespace = kubernetes_namespace.nextcloud.metadata[0].name
  # ponytail: first-boot file copy onto local-path storage can run past 10 min
  # on a Docker-Desktop bind mount; keep this >= the startupProbe ceiling in
  # helm/nextcloud/values.yaml (120 x 10s).
  timeout           = 1500
  dependency_update = true

  # ponytail: postStart OAuth config + hostnames are one big multi-line shell
  # string (see helm/nextcloud/values.yaml) — placeholder substitution on the
  # rendered file, not --set, matches the Tiltfile.
  values = [
    replace(replace(replace(replace(replace(
      file("${path.module}/../helm/nextcloud/values.yaml"),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["nextcloud"]),
      "__APP_HOST__", "nextcloud.${local.tailnet_domain}"),
      "__NEXTCLOUD_OIDC_CLIENT_ID__", var.nextcloud_oidc_client_id),
    "__NEXTCLOUD_OIDC_CLIENT_SECRET__", var.nextcloud_oidc_client_secret)
  ]

  set_sensitive {
    name  = "nextcloud.nextcloud.password"
    value = var.nextcloud_admin_password
  }

  # ponytail: this wrapper chart's own plain mariadb:11 StatefulSet (not bitnami).
  # nextcloud.externalDatabase.password must match mariadb.password.
  set_sensitive {
    name  = "nextcloud.externalDatabase.password"
    value = var.nextcloud_db_password
  }

  set_sensitive {
    name  = "mariadb.password"
    value = var.nextcloud_db_password
  }

  set_sensitive {
    name  = "mariadb.rootPassword"
    value = var.nextcloud_db_root_password
  }

  depends_on = [kubernetes_namespace.nextcloud]
}

# ponytail: mirrors Tiltfile's nextcloud-promote-admin — no-op until ADMIN_EMAIL
# has logged in via SSO at least once, safe to re-run any time.
resource "null_resource" "nextcloud_promote_admin" {
  triggers = {
    admin_email = var.admin_email
    script_hash = filesha1("${path.module}/../helm/nextcloud/promote-admin.sh")
  }

  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    command     = "'${local.bash_bin}' '${local_file.nextcloud_promote_admin_script.filename}'"
  }

  depends_on = [helm_release.nextcloud, local_file.nextcloud_promote_admin_script]
}

resource "local_file" "nextcloud_promote_admin_script" {
  filename = "${path.module}/.nextcloud-promote-admin.sh"
  content = join("\n", [
    "kubectl exec -i -n nextcloud deploy/nextcloud -- env ADMIN_EMAIL='${var.admin_email}' bash < '${abspath(path.module)}/../helm/nextcloud/promote-admin.sh'",
    "",
  ])
}
