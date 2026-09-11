# CLAUDE.md

Project structure, conventions, and current progress live in **[AGENT.md](./AGENT.md)** —
read it first. This file adds Claude-Code-specific notes.

@AGENT.md

## Working here

- **Tilt path and Terraform path must stay in sync.** If you touch
  `helm/<app>/Tiltfile` or `helm/<app>/values.yaml`, make the matching change
  in `terraform/<app>.tf`, and vice versa.
- Secrets flow one way: edit `.env` → `scripts/linux/gen-tfvars.sh` →
  `tofu apply`. Never edit `terraform/local.auto.tfvars` or a live Secret
  directly. `helm/<app>/values.yaml` carries `__PLACEHOLDER__` tokens the
  `.tf` swaps in. A `TF_VAR_*` line in `.env` that has no `variable {}` block
  makes `tofu plan` warn "undeclared variable" — remove it from `.env` too.
- `ponytail:` comments are intentional. Don't remove a simplification without
  a reason; if you do change one, update the comment.
- Prefer editing `values.yaml` + `tofu apply` over `kubectl set env` /
  `kubectl patch`. Live-only changes drift from the repo.
- **DB/cache is shared:** `helm/postgres` + `helm/redis`, one pod each,
  cross-namespace at `postgres.postgres.svc.cluster.local` /
  `redis.redis.svc.cluster.local`. `postgres/templates/postgres.yaml`'s
  `initdb` ConfigMap creates a role+db per app and **only runs on first init**
  — a schema change there needs a PVC wipe or a manual `psql` fix-up.

## This environment

- **caveman + ponytail rulesets are active** (see the session banners) — terse
  prose, laziest-solution-that-works. They govern chat/output style and build
  decisions, not committed code/comments/docs (those stay normal prose).
- Auto-memory lives under `.claude/projects/.../memory/` — check `MEMORY.md`
  for prior findings (e.g. the `opencode → omp` migration note).
- Some `tofu apply` / `kubectl` mutations get blocked by the auto-mode
  classifier. When that happens, make the file changes and hand the user the
  exact commands to run.

## Gotchas found the hard way

- `omp --mode rpc` ignores `config.yml`'s `model:` — it must be passed
  `--model` (done in `pod-openai.py`), and the pod's `models.db` must be
  populated with `omp models refresh` first.
- omp's `models.yml` for v18.x: `baseUrl` **without** `/v1`, and
  `auth: none` on the ollama provider, or discovery silently returns nothing.
- `qwen3-coder-next` (80B) OOMs on the host — use `qwen3.8:27b`.
- n8n blocks `$env` in node expressions by default
  (`N8N_BLOCK_ENV_ACCESS_IN_NODE=false` is set).
- n8n 2.x rejects `active`/`tags` on `POST /workflows`; activate via
  `POST /workflows/{id}/activate`.
- Git Bash rewrites absolute in-pod paths (and `/bin/sh`) passed to
  `kubectl exec` — prefix with `MSYS_NO_PATHCONV=1`.
- `kubernetes.core.k8s_exec` returns `return_code` (not `rc`), and may omit
  it entirely on success — gate `until:` / `failed_when:` on `stdout` content.
- **Shared postgres:** role name == db name for every app **except GitLab**
  (role `gitlab`, db `gitlabhq_production`).
- **GitLab CE has no group webhooks** (Premium) — `gitlab-webhook.yml`
  registers project-level hooks. GitLab also blocks webhook URLs on the
  local network until `allow_local_requests_from_web_hooks_and_services` is on
  (the playbook flips it). Every GitLab PAT dies with the DB, so the playbook
  mints its own via `rails runner`.
- GitLab rejects weak first-admin passwords ("commonly used combinations") —
  `gitlab_root_password` must be random-ish, not dictionary words.
- Authentik's `null_resource.authentik_app_providers` can run before the
  default OAuth blueprints import — every provider ends up with no scope
  mappings and every OIDC login fails "Insufficient scope". The script now
  waits for the `openid`/`email`/`profile` mappings before assigning them.
- **Tailscale shared ProxyGroup** (`terraform/tailscale-ingress.tf`): all app
  Ingresses front one node via a Tailscale Service each. The tailnet policy
  needs THREE things or apps are silently `unreachable`:
  1. OAuth client scope **Services=write** (else operator 404s creating the
     Service).
  2. `autoApprovers.services` for `tag:k8s` (else Services never advertised —
     operator logs `No Pods are advertising Tailscale Service yet`).
  3. **Both** a `dst: ["tag:k8s"]` grant AND a `dst: ["svc:…"]` grant for
     `autogroup:member`. The `svc:` grant alone: client netmap has the service
     names but `peer count` is missing the ProxyGroup node → every
     `<app>.<tailnet>.ts.net` times out.
  Rapid delete/recreate of the tailscale proxies burns Let's Encrypt's "10 new
  ACME registrations / IP / 3h" — wait it out, don't churn.
- **In-cluster can't reach the tailnet hostname.** Pods have no route to the
  Tailscale Service VIP, so any app that does OIDC *discovery* server-side
  against `authentik.<tailnet>` times out. `terraform/coredns.tf` fixes it:
  a `coredns-custom` rewrite points that name at traefik in-cluster, plus a
  traefik vhost for it with a homelab-CA cert. Apps consuming it must trust the
  homelab CA (`kubernetes_secret.*_homelab_ca` — minio via the chart's
  `trustedCertsSecret`, openwebui via an init-container bundle). gitlab /
  grafana / litellm sidestep it by hard-coding `authentik-server.authentik.svc`
  for their server-side endpoints and only using the external URL for the
  browser redirect — do that for new apps when the app allows split endpoints.
