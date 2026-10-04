# ponytail: one secret set reused across sit/uat/production (homelab, not 3
# isolated environments needing real secret separation) - split later if that
# changes.

variable "phase_authentik_secret_key" {
  type      = string
  sensitive = true
}

variable "phase_authentik_bootstrap_password" {
  type      = string
  sensitive = true
}

variable "phase_authentik_bootstrap_token" {
  type      = string
  sensitive = true
}

# ponytail: dedicated postgres:16 + redis:7-alpine per phase cluster (same
# official images as helm/postgres / helm/redis on internal) back authentik
# here — replaces the goauthentik chart's bundled bitnami postgresql/redis
# subcharts, avoided per policy.
variable "phase_shared_db_password" {
  type      = string
  sensitive = true
}

variable "phase_unleash_admin_password" {
  type      = string
  sensitive = true
}

variable "phase_vault_root_token" {
  type      = string
  sensitive = true
}

variable "phase_meilisearch_master_key" {
  type      = string
  sensitive = true
}

variable "phase_minio_root_password" {
  type      = string
  sensitive = true
}

variable "enable_authentik" {
  type    = bool
  default = true
}

variable "enable_traefik" {
  type    = bool
  default = true
}

variable "enable_unleash" {
  type    = bool
  default = true
}

variable "enable_vault" {
  type    = bool
  default = true
}

variable "enable_kafka" {
  type    = bool
  default = true
}

variable "enable_meilisearch" {
  type    = bool
  default = true
}

variable "enable_minio" {
  type    = bool
  default = true
}

variable "enable_apicurio" {
  type    = bool
  default = true
}

variable "enable_opencost" {
  type    = bool
  default = true
}

# ponytail: identifies this cluster's series in internal's Mimir (external_labels
# on this cluster's own opencost-prometheus release) - set explicitly per root
# module (sit/uat/production), not derived from anything, so it stays correct
# if a dir is ever renamed independent of its k3d cluster name.
variable "cluster_id" {
  type = string
}

# matches terraform/internal's var of the same name - the NodePort on internal's
# k3d loadbalancer this cluster's opencost-prometheus remote_writes to (see opencost.tf).
variable "mimir_push_port" {
  type    = number
  default = 30510
}

# matches terraform/internal's var of the same name - the NodePort on internal's
# k3d loadbalancer this cluster's log-shipper pushes logs to (see log-shipper.tf).
variable "loki_push_port" {
  type    = number
  default = 30511
}

# matches terraform/internal's var of the same name - the NodePort on internal's
# k3d loadbalancer this cluster's log-shipper pushes traces to (see log-shipper.tf).
variable "tempo_push_port" {
  type    = number
  default = 30512
}

# ponytail: the host port THIS cluster's own k3d loadbalancer maps kafka's
# NodePort to (kafka.tf) - must be unique per phase cluster since they all
# share the same Docker host, matched by scripts/*/create-cluster.sh and
# helm/kafka-ui/values.yaml's bootstrapServers. No default - each root module
# passes its own (30901/30902/30903).
variable "kafka_nodeport" {
  type = number
}

# apicurio.tf's kubernetes_service.apicurio_external — same reversed-bridge
# pattern as kafka_nodeport above. No default - each root module passes its
# own (30911/30912/30913).
variable "apicurio_nodeport" {
  type = number
}
