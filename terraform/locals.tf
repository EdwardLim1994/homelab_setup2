locals {
  # ponytail: tailnet MagicDNS suffix — explicit var wins, else derive it by
  # dropping the first label of ts_host (desktop-x.tail1234.ts.net -> tail1234.ts.net).
  tailnet_domain = coalesce(
    var.tailnet_domain,
    join(".", slice(split(".", var.ts_host), 1, length(split(".", var.ts_host)))),
  )

  # Each app's tailscale Ingress: <key> becomes the MagicDNS hostname
  # (<key>.<tailnet_domain>), backed by <namespace>/<service>:<port>.
  tailscale_apps = {
    authentik     = { namespace = "authentik", service = "authentik-server", port = 80 }
    gitlab        = { namespace = "gitlab", service = "gitlab-webservice-default", port = 8181 }
    minio         = { namespace = "minio", service = "minio", port = 9000 }
    minio-console = { namespace = "minio", service = "minio-console", port = 9001 }
    n8n           = { namespace = "n8n", service = "n8n", port = 5678 }
    sonarqube     = { namespace = "sonarqube", service = "sonarqube-sonarqube", port = 9000 }
    nextcloud     = { namespace = "nextcloud", service = "nextcloud", port = 8080 }
    argocd        = { namespace = "argocd", service = "argocd-server", port = 80 }
    grafana       = { namespace = "observability", service = "observability-grafana", port = 80 }
    litellm       = { namespace = "litellm", service = "litellm", port = 4000 }
    openwebui     = { namespace = "openwebui", service = "openwebui", port = 8080 }
  }

  # https://<app>.<tailnet_domain> for each — used to build OIDC redirect URIs.
  app_url = { for k, v in local.tailscale_apps : k => "https://${k}.${local.tailnet_domain}" }

  authentik_url = "https://authentik.${local.tailnet_domain}"

  # ponytail: a bare "bash" in provisioner interpreters can resolve to WSL's
  # bash on Windows (System32\bash.exe), which can't open the C:/... paths these
  # scripts use ("No such file or directory"). Prefer Git Bash when it's there;
  # plain "bash" everywhere else (Linux/macOS).
  bash_bin = coalesce(
    var.bash_bin,
    fileexists("C:/Program Files/Git/bin/bash.exe") ? "C:/Program Files/Git/bin/bash.exe" : "bash",
  )
}
