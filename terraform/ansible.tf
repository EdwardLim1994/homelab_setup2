resource "kubernetes_namespace" "ansible" {
  metadata {
    name = "ansible"
  }
}

# ponytail: the n8n SDLC flows + seed.sh — mounted at /flows in the runner,
# seeded by playbooks/n8n.yml. Kept out of the helm chart package via
# helm/ansible/.helmignore (nothing templates them).
resource "kubernetes_config_map" "ansible_n8n_flows" {
  metadata {
    name      = "ansible-n8n-flows"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
  data = {
    for f in fileset("${path.module}/../helm/ansible/flows", "*") :
    f => file("${path.module}/../helm/ansible/flows/${f}")
  }
}

# ponytail: the SDLC OpenWebUI pipe (helm/ansible/pipe/sdlc_pipe.py) — mounted
# at /pipe, same pattern as ansible_n8n_flows. Kept out of the helm chart
# package via helm/ansible/.helmignore.
resource "kubernetes_config_map" "ansible_pipe" {
  metadata {
    name      = "ansible-pipe"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
  data = {
    for f in fileset("${path.module}/../helm/ansible/pipe", "*") :
    f => file("${path.module}/../helm/ansible/pipe/${f}")
  }
}

resource "kubernetes_secret" "ansible_secrets" {
  metadata {
    name      = "ansible-secrets"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
  # ponytail: one Secret, envFrom'd into the runner — playbooks read any key via
  # lookup('env', '<key>'). Source of truth is .env (TF_VAR_*). Rotate a token:
  # edit .env, `tofu apply -target=kubernetes_secret.ansible_secrets`, then
  # `scripts/ansible-run.sh mcp-servers`.
  data = {
    n8n_owner_email       = var.admin_email
    n8n_owner_password    = var.n8n_owner_password
    grafana_mcp_token     = var.grafana_mcp_token
    sonarqube_mcp_token   = var.sonarqube_mcp_token
    gitlab_mcp_token      = var.gitlab_mcp_token
    gitlab_mcp_auth_token = var.gitlab_mcp_auth_token
    omp_gitlab_token = var.omp_gitlab_token
    # ponytail: n8n API key playbooks/n8n.yml uses for the mcp-servers-n8n
    # deployment — persisted here instead of minted fresh every run (n8n
    # only ever returns the raw secret once, at creation). Blank on first
    # run: n8n.yml mints one and prints it so you can paste it into .env.
    n8n_mcp_api_key       = var.n8n_mcp_api_key
    # ponytail: SSO-only login (ENABLE_LOGIN_FORM=False) means openwebui.yml
    # can't script a password login like n8n.yml does. Blank on first run —
    # log into OpenWebUI once via the browser (SSO), Settings -> Account ->
    # API Keys -> generate, paste it here.
    openwebui_api_key = var.openwebui_api_key
    litellm_master_key    = var.litellm_master_key
    gitlab_webhook_secret = var.gitlab_webhook_secret
    gitlab_group_id       = var.gitlab_group_id
  }
}

# ponytail: lets the ansible-ns runner SA patch env into the mcp-servers
# Deployments (mcp-servers.yml). Scoped to that one namespace, get+patch only.
resource "kubernetes_role" "ansible_mcp_patch" {
  metadata {
    name      = "ansible-mcp-patch"
    namespace = "mcp-servers"
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "patch"]
  }
  depends_on = [kubernetes_namespace.mcp_servers]
}

resource "kubernetes_role_binding" "ansible_mcp_patch" {
  metadata {
    name      = "ansible-mcp-patch"
    namespace = "mcp-servers"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_mcp_patch.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

# ponytail: gitlab-webhook.yml runs `rails runner` inside the webservice pod to
# mint a fresh PAT (PATs die with the DB) — needs pod read + exec in `gitlab`.
resource "kubernetes_role" "ansible_gitlab_exec" {
  metadata {
    name      = "ansible-gitlab-exec"
    namespace = "gitlab"
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["get", "create"]
  }
  depends_on = [kubernetes_namespace.gitlab]
}

resource "kubernetes_role_binding" "ansible_gitlab_exec" {
  metadata {
    name      = "ansible-gitlab-exec"
    namespace = "gitlab"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_gitlab_exec.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

resource "helm_release" "ansible" {
  name      = "ansible"
  chart     = "${path.module}/../helm/ansible"
  namespace = kubernetes_namespace.ansible.metadata[0].name
  # ponytail: nothing runs on apply — the CronJob is suspended. Trigger playbooks
  # with scripts/ansible-run.sh.
  wait = false

  # ponytail: the helm provider doesn't hash local chart files, so edits to
  # playbooks/values wouldn't redeploy on their own. Fold a dir hash into an
  # unused value so any change forces an upgrade (mirrors omp.tf's trigger).
  set {
    name = "chartHash"
    value = sha1(join(",", [
      for f in fileset("${path.module}/../helm/ansible", "**") : filesha1("${path.module}/../helm/ansible/${f}")
      if !startswith(f, "flows/") && !startswith(f, "pipe/") # both go in via configmaps above, not the chart
    ]))
  }

  depends_on = [
    kubernetes_config_map.ansible_n8n_flows,
    kubernetes_config_map.ansible_pipe,
    kubernetes_secret.ansible_secrets,
  ]
}
