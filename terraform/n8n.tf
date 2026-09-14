resource "kubernetes_namespace" "n8n" {
  metadata {
    name = "n8n"
  }
}

resource "kubernetes_config_map" "n8n_oidc_hooks" {
  metadata {
    name      = "n8n-oidc-hooks"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }
  data = {
    "hooks.js" = file("${path.module}/../helm/n8n/hooks.js")
  }
  depends_on = [kubernetes_namespace.n8n]
}

# ponytail: the cweagans/n8n-oidc hook does OIDC discovery + token exchange
# server-side (Node's https client) against OIDC_ISSUER_URL, the external
# tailnet URL — coredns.tf rewrites that to in-cluster traefik, which serves
# a homelab-CA cert Node doesn't trust ("unable to verify the first
# certificate"). Same read-and-copy pattern as minio.tf/openwebui.tf/
# argocd.tf; separate data source name per module-uniqueness rule. Unlike
# argocd's Go binary, Node natively supports an *additive* extra-CA file
# (NODE_EXTRA_CA_CERTS) — no need for argocd's combine-and-overwrite-the-
# system-bundle trick.
data "kubernetes_secret" "homelab_ca_n8n" {
  metadata {
    name      = "homelab-ca-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  depends_on = [null_resource.homelab_ca_ready]
}

resource "kubernetes_secret" "n8n_homelab_ca" {
  metadata {
    name      = "homelab-ca"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca_n8n.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.n8n, data.kubernetes_secret.homelab_ca_n8n]
}

resource "helm_release" "n8n" {
  name              = "n8n"
  chart             = "${path.module}/../helm/n8n"
  namespace         = kubernetes_namespace.n8n.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(replace(replace(
      file("${path.module}/../helm/n8n/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
    "__APP_URL__", local.app_url["n8n"]),
  ]

  set_sensitive {
    name  = "n8n.encryptionKey"
    value = var.n8n_encryption_key
  }

  set_sensitive {
    name  = "n8n.main.extraEnvVars.OIDC_CLIENT_ID"
    value = var.n8n_oidc_client_id
  }

  set_sensitive {
    name  = "n8n.main.extraEnvVars.OIDC_CLIENT_SECRET"
    value = var.n8n_oidc_client_secret
  }

  set_sensitive {
    name  = "n8n.main.extraEnvVars.LITELLM_MASTER_KEY"
    value = var.litellm_master_key
  }

  set_sensitive {
    name  = "n8n.main.extraEnvVars.GITLAB_WEBHOOK_SECRET"
    value = var.gitlab_webhook_secret
  }

  set_sensitive {
    name  = "n8n.externalPostgresql.password"
    value = var.shared_db_password
  }

  # ponytail: not sensitive, just terraform-only (like the CA-trust wiring
  # elsewhere) — Tilt has no tailnet ingress/coredns rewrite, so the
  # homelab-ca Secret this points at won't exist there, and Node errors on
  # a missing NODE_EXTRA_CA_CERTS file. Leaving it unset in values.yaml
  # keeps the Tilt path from ever hitting that.
  set {
    name  = "n8n.main.extraEnvVars.NODE_EXTRA_CA_CERTS"
    value = "/homelab-ca/ca.crt"
  }

  # ponytail: flow seeding + owner setup + API-key minting all moved to the
  # ansible runner — `scripts/ansible-run.sh n8n`.

  # ponytail: the helm provider doesn't hash local chart template files (only
  # values), so an edit to e.g. templates/omp-agent-rbac.yaml wouldn't
  # redeploy on its own — tofu apply silently reports "no differences".
  # Mirrors helm_release.ansible's identical fix.
  set {
    name = "chartHash"
    value = sha1(join(",", [
      for f in fileset("${path.module}/../helm/n8n", "**") : filesha1("${path.module}/../helm/n8n/${f}")
    ]))
  }

  # sdlc namespace must exist first — helm/n8n/templates/omp-agent-rbac.yaml
  # binds n8n's ServiceAccount to a Role in that namespace.
  depends_on = [kubernetes_namespace.n8n, kubernetes_config_map.n8n_oidc_hooks, kubernetes_secret.n8n_homelab_ca, helm_release.postgres, kubernetes_namespace.sdlc]
}
