resource "kubernetes_namespace" "minio" {
  metadata {
    name = "minio"
  }
}

# ponytail: MinIO trusts the homelab CA so its server-side OIDC discovery to
# authentik.<tailnet> (rewritten to traefik in terraform/coredns.tf) validates.
# Same read-and-copy pattern as openwebui.tf — separate data source name
# (used to piggyback on mattermost.tf's before that file was removed;
# resource names must be unique per type per module).
data "kubernetes_secret" "homelab_ca_minio" {
  metadata {
    name      = "homelab-ca-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  depends_on = [null_resource.homelab_ca_ready]
}

resource "kubernetes_secret" "minio_homelab_ca" {
  metadata {
    name      = "minio-homelab-ca"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca_minio.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.minio, data.kubernetes_secret.homelab_ca_minio]
}

resource "helm_release" "minio" {
  name              = "minio"
  chart             = "${path.module}/../../helm/minio"
  namespace         = kubernetes_namespace.minio.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(replace(replace(replace(replace(
      file("${path.module}/../../helm/minio/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["minio"]),
      "__CONSOLE_URL__", local.app_url["minio-console"]),
    "__MINIO_TRUSTED_CA_SECRET__", kubernetes_secret.minio_homelab_ca.metadata[0].name),
  ]

  set_sensitive {
    name  = "minio.rootPassword"
    value = var.minio_root_password
  }

  set_sensitive {
    name  = "minio.environment.MINIO_IDENTITY_OPENID_CLIENT_ID"
    value = var.minio_oidc_client_id
  }

  set_sensitive {
    name  = "minio.environment.MINIO_IDENTITY_OPENID_CLIENT_SECRET"
    value = var.minio_oidc_client_secret
  }

  depends_on = [kubernetes_namespace.minio, kubernetes_secret.minio_homelab_ca]
}

# ponytail: chart's own `buckets[]` schema (helm/minio's bundled chart) has no
# lifecycle field — set retention imperatively via mc, same `kubectl run` trick
# as harbor's OIDC config. `mc ilm rule add` has no upsert-by-id — guard with
# a check so repeat applies (this only re-runs when minio itself redeploys,
# not every apply) don't pile up duplicate (harmless but messy) rules.
resource "null_resource" "postgres_backups_retention" {
  triggers = {
    minio_release = helm_release.minio.metadata[0].revision
  }

  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    command     = <<-EOT
      set -e
      kubectl --context ${var.kube_context} run minio-ilm-config-$RANDOM --rm -i --restart=Never \
        --image=minio/mc:latest --image-pull-policy=IfNotPresent -n minio --command -- \
        sh -c 'mc alias set local http://minio.minio.svc.cluster.local:9000 "admin" "${var.minio_root_password}" >/dev/null && if [ -z "$(mc ilm rule ls local/postgres-backups 2>/dev/null)" ]; then mc ilm rule add --expire-days 7 local/postgres-backups; else echo "lifecycle rule already exists, skipping"; fi'
    EOT
  }

  depends_on = [helm_release.minio]
}
