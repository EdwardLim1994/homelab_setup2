variable "kubeconfig" {
  description = "Path to kubeconfig. Point this at k3d's for local, a real cluster's for prod."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to deploy into (e.g. \"k3d-dev\", k3d's default naming for a cluster created as `k3d cluster create dev`)."
  type        = string
  default     = "k3d-dev"
}

variable "namespace" {
  description = "Namespace every services/* chart deploys into — matches each chart's own values.yaml."
  type        = string
  default     = "infra"
}

# cert-manager's CRDs + webhook (ValidatingWebhookConfiguration) are cluster-scoped — when
# several namespace-isolated environments (e.g. sit/uat/staging share one cluster with namespace
# physical cluster/kube_context, only one of them can actually own the cert-manager controller;
# a second helm_release.cert-manager on the same cluster fails ("CRD exists and cannot be
# imported"/webhook name collision). cert-manager-config (the per-namespace selfSigned Issuer)
# still applies every time — only the shared controller is gated.
# Irrelevant (leave default true) when each environment actually has its own separate cluster,
# the normal case this repo's kube_context/namespace split is designed for.
variable "install_cert_manager" {
  description = "Install the shared cert-manager controller/CRDs. Set false for every environment after the first when multiple environments share one physical cluster."
  type        = bool
  default     = true
}

variable "tailscale" {
  description = "Apply values-tailscale.yaml overrides for authentik/minio/monitoring — needed whenever the cluster is accessed via Tailscale (off-LAN), regardless of environment."
  type        = bool
  default     = true
}

variable "tailscale_hostname" {
  description = "Tailscale MagicDNS hostname of this machine (e.g. raspberrypi94.tail60240b.ts.net). Used as the redirect/auth host in values-tailscale.yaml. Required when tailscale = true."
  type        = string
  default     = ""
  validation {
    condition     = !var.tailscale || var.tailscale_hostname != ""
    error_message = "tailscale_hostname must be set when tailscale = true."
  }
}

variable "environment" {
  description = "\"dev\" (minikube — dev-mode secrets baked into each chart's values.yaml) or one of the real clusters \"sit\"/\"uat\"/\"staging\"/\"prod\" (each chart's own values-nondev.yaml, where one exists, layers on top as a shared override — nothing today differs between the four real clusters, so they share one file)."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "sit", "uat", "staging", "prod"], var.environment)
    error_message = "environment must be one of \"dev\", \"sit\", \"uat\", \"staging\", \"prod\"."
  }
}

# Real secrets for a non-dev deploy — never given a default, so a sit/uat/staging/prod apply
# fails fast instead of silently reusing a dev placeholder. Unused (and left unset) when
# environment = "dev".
variable "authentik_secret_key" {
  description = "Authentik's SECRET_KEY (non-dev only)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "authentik_postgres_password" {
  description = "Password for authentik-postgresql's \"authentik\" bootstrap user (non-dev only) — this is the DB credential in full, static for the life of the deploy (no dynamic-credential provisioner rotates it)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "authentik_bootstrap_password" {
  description = "authentik's akadmin bootstrap password, first-install only (non-dev only)."
  type        = string
  default     = ""
  sensitive   = true
}
