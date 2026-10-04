module "platform_apps" {
  source = "../modules/platform-apps"
  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  phase_authentik_secret_key         = var.phase_authentik_secret_key
  phase_authentik_bootstrap_password = var.phase_authentik_bootstrap_password
  phase_authentik_bootstrap_token    = var.phase_authentik_bootstrap_token
  phase_shared_db_password           = var.phase_shared_db_password
  phase_unleash_admin_password       = var.phase_unleash_admin_password
  phase_vault_root_token             = var.phase_vault_root_token
  phase_meilisearch_master_key       = var.phase_meilisearch_master_key
  phase_minio_root_password          = var.phase_minio_root_password
  cluster_id                         = "sit"
  kafka_nodeport                     = 30901
  apicurio_nodeport                  = 30911
}
