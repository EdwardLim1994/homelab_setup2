# AGENT.md

Orientation for coding agents working in this repo. Human-facing setup lives in
`README.md`; this file is about *how the pieces fit* and *where things stand*.

## What this is

A self-hosted homelab that runs on a local **k3d** cluster. One Authentik SSO
in front of everything, every app reachable over Tailscale MagicDNS
(`https://<app>.<tailnet>.ts.net`) and on the LAN (`https://<app>.local`).

Apps: Authentik, GitLab (+ runner), MinIO, n8n, SonarQube, Nextcloud, ArgoCD,
an LGTM observability stack, LiteLLM, OpenWebUI, a set of MCP
servers, and an in-cluster coding-agent stack (`omp` / oh-my-pi).

## Two deploy paths, kept in lockstep

| Path | Files | Use |
|---|---|---|
| **Tilt** | `helm/<app>/Tiltfile` + root `Tiltfile` | fast local iteration, hot reload, dev-fixed secrets |
| **Terraform (OpenTofu)** | `terraform/<app>.tf` | deliberate "real" deploy, no reload |

**Rule:** every `helm/<app>/Tiltfile` has a 1:1 `terraform/<app>.tf` mirror —
same env vars, same OIDC wiring. Change one, change the other.

Both read secrets from the **same root `.env`**. Tiltfiles load `.env`
directly; Terraform reads `terraform/local.auto.tfvars`, regenerated from
`.env` by `scripts/{linux,windows}/gen-tfvars.*` (gitignored, never hand-edit).

### Secret substitution convention

`helm/<app>/values.yaml` contains `__PLACEHOLDER__` tokens. Terraform swaps
them via a `replace(replace(... file(values.yaml) ...))` chain in the app's
`.tf`; the Tiltfile does the equivalent with `--set` or string replace.
Non-secret dev defaults live inline in `values.yaml`. `set_sensitive` in the
`.tf` is used for values that must not appear in plan output.

### Authentik provisioning

`terraform/authentik.tf` has two `null_resource` provisioners that create
config no `helm_release` owns:

- `authentik_app_providers` — runs `helm/authentik/provision-app-providers.py`
  to create every app's OAuth2/SAML provider inside Authentik. Without it,
  every "Log in with Authentik" button 404s.
- `authentik_github_source` — GitHub as a login source for Authentik's own
  admin panel.

Both re-run on `triggers` when their secrets or the Python script change.

## Repo layout

```
helm/<app>/            Helm chart + Tiltfile (dev path)
helm/<app>/values.yaml Chart values with __PLACEHOLDER__ secret tokens
terraform/<app>.tf     Matching Terraform resource (prod path)
terraform/locals.tf    app_url map, authentik_url, shared locals
terraform/variables.tf All TF_VAR_* inputs + dev defaults
scripts/linux/*.sh     bash; scripts/windows/*.ps1  PowerShell 7+ (equivalent)
.env / .env.example    single source of truth for both paths
k3d-storage/           host-path mount backing the cluster's local-path PVs
                       (dir tracked via .gitkeep — never `git clean -fdx` it
                        while the cluster runs, it breaks every PVC mount)
```

## Shared Postgres + Redis

One `postgres:16` pod (`helm/postgres`, namespace `postgres`, service
`postgres.postgres.svc.cluster.local:5432`) backs **authentik, gitlab, litellm,
n8n, sonarqube** — one LOGIN role + owned database per app, all
sharing `var.shared_db_password`, created by the chart's `initdb` ConfigMap on
**first init only**. Role name == db name for everyone except GitLab (role
`gitlab`, db `gitlabhq_production`); initdb also adds `pg_trgm` / `btree_gist`
there so the gitlab role never needs superuser.
`args: ["-c", "max_locks_per_transaction=512"]` for GitLab's schema load.

One `redis:7-alpine` pod (`helm/redis`, namespace `redis`, service
`redis.redis.svc.cluster.local:6379`, no auth, no persistence): **gitlab** on
logical DB 0 (its components' default), **authentik** on DB 1
(`AUTHENTIK_REDIS__DB`).

Each consumer's `.tf` has `depends_on = [helm_release.postgres(, .redis)]` and
its Tiltfile `resource_deps=['postgres'(, 'redis')]`. **nextcloud keeps its own
MariaDB** (different engine); **argocd keeps its bundled redis** (tightly
coupled to the argo-cd subchart). Old per-app `<app>-postgres` /
`<app>-redis` templates are gone — after switching, orphan
`data-<app>-postgres-0` PVCs must be deleted by hand (StatefulSet PVCs aren't
pruned).

## Tailscale ingress

`terraform/tailscale.tf` (operator) + `terraform/tailscale-ingress.tf` (one
`tailscale`-class Ingress per app, plus the `ProxyGroup` CR inline,
`replicas: 1`). All 11 Ingresses carry
`tailscale.com/proxy-group: homelab-ingress` and share that **one** ProxyGroup
node. One tailnet device fronts everything; each app still gets its own
`<app>.<tailnet>.ts.net` name + Let's Encrypt cert, delivered as a **Tailscale
Service** (VIPService) the node advertises.

Tailnet policy MUST have (see `tailscale.tf` header for the exact JSON):
- OAuth client scopes **Devices/Core + Keys/Auth Keys + Services**, all write.
- `autoApprovers.services` for `tag:k8s` — else Services sit unapproved and the
  node never advertises them.
- **Two** grants for `autogroup:member`: `dst: tag:k8s` AND `dst: [svc:…all 11…]`.
  The `svc:` grant alone puts the service names in the client netmap but not the
  node backing them — every URL then times out ("unreachable" in `list-urls`).

Was one device *per app* before; the per-app model burned Let's Encrypt's
"10 new ACME registrations / IP / 3h" on any rebuild and left a pile of stale
devices. `list-urls.sh` reads the operator-assigned hostname from each
`ts-<app>` Ingress status, so a `-N` suffix (name still held by a stale device)
doesn't break it.

**Split-horizon DNS** (`terraform/coredns.tf`): pods can't route to the Tailscale
Service VIP, so an app doing OIDC discovery server-side against
`https://authentik.<tailnet>` just times out. A `coredns-custom` rewrite points
that name at traefik in-cluster + a traefik vhost serves it with a homelab-CA
cert; the consuming app trusts that CA (minio via the chart's
`trustedCertsSecret`, openwebui via an init container). Browser traffic is
untouched. Terraform-only — Tilt has no tailnet ingress. Apps that *can* split
browser vs backend endpoints (gitlab/grafana/litellm) skip all this and just
point server-side calls at `authentik-server.authentik.svc`.

## The coding-agent stack (`omp`)

Migrated from `opencode` to **oh-my-pi (`omp`)**. `omp` has **no HTTP server** —
it's CLI / `--mode rpc` (newline-JSON over stdio) / ACP only.

- `helm/omp/` renders: one always-on-ish `omp` Deployment (scale-to-zero),
  an `omp-slot-1..N` pool, one `omp-<role>` Deployment per entry in
  `values.yaml: roles` (12 SDLC roles), and `omp-adapter`.
- **Every omp pod runs `helm/omp/adapter/pod-openai.py` as PID 1** — an
  OpenAI-compatible API on `:4096` wrapping one persistent `omp --mode rpc`
  child (requests serialized by a lock).
- `helm/omp/adapter/server.py` (`omp-adapter`) is a scale-to-zero waker + flat
  proxy so LiteLLM can list the omp pods as models.
- `helm/litellm/templates/config.yaml` registers `omp` and `omp-<role>` as
  models (`api_base: http://omp-adapter.omp.svc:8000/v1`) plus the host
  Ollama models, plus `pass_through_endpoints` for auth'd/logged direct hops.
- omp config is baked into the image (`helm/omp/Dockerfile`): `models.yml`
  (Ollama provider), `config.yml` (model choice), `RULES.md` (caveman/ponytail
  rulesets), skills under `~/.omp/agent/skills/`.
- **Model backend is host Ollama** at `host.docker.internal:11434`. omp's
  brain and LiteLLM's real models both depend on it being up.

See `helm/omp/SPAWN.md` for the spawn/despawn flows and role pods.

## n8n SDLC flows

`helm/ansible/flows/F-*.json` — 29 n8n workflows implementing an SDLC pipeline,
originally driven by Mattermost slash commands + GitLab/CI webhooks. Seeded by
`helm/ansible/flows/seed.sh`, run from `helm/ansible/playbooks/n8n.yml`
(mints an n8n API key, then upserts the flows). Flow files are mounted at
`/flows` in the ansible runner via the `ansible-n8n-flows` ConfigMap
(`terraform/ansible.tf`, built from the files — not the helm chart).

`seed.sh` strips read-only keys (`active`, `tags`) before `POST /api/v1/workflows`
and activates via `POST /workflows/{id}/activate` (n8n 2.x).

**Mattermost was removed** (see "Current progress" below) — the flow JSON
files still carry `mattermostApi` credential refs and Mattermost-shaped nodes
(`F-28-chat.json`'s outgoing-webhook trigger, the notification posts in the
release/UAT/rollback flows). They're stale until updated to a new
notification target; not yet done.

## Ansible runner

`helm/ansible/` renders a **permanently-suspended CronJob**. Playbooks run as
one-shot Jobs cloned from it by `scripts/{linux,windows}/ansible-run.*`:

```
scripts/linux/ansible-run.sh              # ALL playbooks, fanned out in parallel
scripts/linux/ansible-run.sh n8n          # playbooks/n8n.yml
scripts/linux/ansible-run.sh omp --syntax-check
```

Playbooks: `n8n.yml`, `mcp-servers.yml`, `omp.yml`, `litellm.yml`. With no
argument the script launches one Job per playbook, all in parallel (no
cross-dependencies now that `mattermost.yml` — the one thing chained after
n8n — is gone). Pass `site` to run the old serial `site.yml` in a single Job
instead. Runner SA is
`ansible-runner`; per-namespace Roles for it live in `terraform/ansible.tf`.

`gitlab-webhook.yml` (+ `gitlab-webhook-project.yml`, included per-project) is
**not** in `site.yml` — bootstrap / disaster-recovery for the n8n SDLC webhook
that feeds flow F-00. Registers a **project-level** hook on every project in the
`sdlc` group (group hooks are Premium; this GitLab is CE) — idempotent, creates
the `sdlc` group if missing. `scripts/ansible-run.{sh,ps1} gitlab-webhook`.
Needs no PAT in `.env` — mints a fresh `sdlc-webhook` api token via `rails
runner` in the webservice pod (needs `pods/exec` in `gitlab`, see
`terraform/ansible.tf`). Uses `gitlab_webhook_secret` from `ansible-secrets`.
Also flips `allow_local_requests_from_web_hooks_and_services` on (n8n is an
in-cluster address). The DevOps pod hooks new repos at `/kickoff`.

## Conventions

- **`ponytail:` comments** mark deliberate simplifications and their upgrade
  path. Respect them; don't "fix" them without cause.
- **`kubernetes.core.k8s_exec`** returns `return_code`/`stdout`, not `rc`.
- k3d image flow: build `k3d-registry:5111/omp-box:dev` (or `localhost:5111/...`),
  push, `crictl rmi` the old tag on the node so `IfNotPresent` re-pulls.
- Git Bash mangles absolute in-pod paths (e.g. `/gitlab/...`) passed to
  `kubectl exec` — prefix with `MSYS_NO_PATHCONV=1`.

## Common commands

```bash
scripts/linux/create-cluster.sh                  # one-time k3d cluster
scripts/linux/dev-up.sh                           # tilt up (dev path)
scripts/linux/gen-tfvars.sh && (cd terraform && tofu apply)   # prod path
scripts/linux/list-urls.sh                        # app URLs + status
scripts/linux/omp-shell.sh                        # interactive omp pod shell
scripts/linux/ansible-run.sh                      # every playbook, parallel fan-out
scripts/linux/ansible-run.sh <playbook>           # just one (n8n / omp / litellm / …)
scripts/linux/ansible-run.sh gitlab-webhook       # not in the default set
kubectl -n omp scale deploy/omp --replicas=1      # wake the agent pod
```

## Current progress

Working and verified end-to-end:

- Full cluster deploys via both Tilt and Terraform.
- Authentik SSO for every app; Tailscale + LAN ingress. (The provisioner now
  waits for Authentik's default OAuth scope mappings before assigning them —
  without that, a fresh Authentik DB leaves every provider unscoped and every
  OIDC login fails "Insufficient scope".)
- **Shared postgres + redis** — one pod each; authentik / gitlab / litellm /
  n8n / sonarqube migrated off their per-app postgres, authentik + gitlab off
  their per-app redis.
- **omp agent stack** — `models.yml` fixed for omp 18.x (`baseUrl` without
  `/v1`, `auth: none`); default model `ollama/qwen3.8:27b` (80B
  `qwen3-coder-next` OOMs); `pod-openai.py` runs `omp models refresh` at boot
  and pins `--model`. `n8n → LiteLLM omp → omp-adapter → omp pod → Ollama`
  returns completions.
- **29 n8n SDLC flows** seeded and active (though Mattermost-shaped — see
  "n8n SDLC flows" above; not yet updated post-removal).
  `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` so `$env.*` resolves.
- **OpenWebUI** — SSO-only login (Authentik), routed through LiteLLM, PWA
  install verified working.
- **MCP servers** — grafana, sonarqube, gitlab, playwright, **n8n**
  (`czlonkowski/n8n-mcp`, docs + management once `n8n.yml` injects the key).
- **GitLab webhook** — `gitlab-webhook.yml` registers a project-level SDLC
  hook on every project in the `sdlc` group (CE has no group hooks).

Known issues / next steps:

- The omp base Deployment idles at `replicas: 0`; first chat after idle waits
  ~1–2 min. Ollama must be running on the host or nothing LLM-shaped works.
- `seed.sh` bails if any workflow exists unless `--force`, and `--force`
  creates duplicates — not a true upsert. Wipe + reseed is the working path.
- Old per-app `data-<app>-postgres-0` / `-postgresql-0` PVCs are orphaned after
  the shared-DB switch — delete them by hand (StatefulSet PVCs aren't pruned).
- `opencode` fully removed (`omp`). `openwebui` was removed in favor of
  Mattermost, then restored (`helm/openwebui`, `terraform/openwebui.tf`) as a
  SSO-only chat UI onto the same LiteLLM backend. OpenWebUI is a PWA out of
  the box (own manifest/service worker); no extra server config beyond the
  HTTPS it already gets from the Tailscale/LAN ingress — install via the
  browser's "Add to Home Screen" (iOS: Safari only) / install icon (desktop
  Chrome/Edge). Login is SSO-only (`ENABLE_LOGIN_FORM: "False"`) — no
  password form.
- **Mattermost removed** (superseded by OpenWebUI for chat — see above). Live
  cluster resources torn down via `tofu destroy`; `helm/mattermost/` and
  `terraform/mattermost.tf` deleted; its shared-postgres db entry, MinIO
  bucket, ansible RBAC/playbook, and script references all removed. **Not**
  cleaned up: the `mattermost` OAuth2Provider/Application still sits in
  Authentik's DB (the provisioner only creates/updates, never deletes —
  remove it by hand via `ak shell` if it matters); the MinIO `mattermost`
  bucket and its shared-postgres role/db aren't dropped either (`initdb` only
  runs on first init — pre-existing data doesn't get cleaned by removing it
  from the chart); the tailnet ACL's `svc:mattermost` grant (external, in the
  Tailscale admin console — outside this repo) needs manual removal; the 29
  n8n flows still reference Mattermost (see "n8n SDLC flows" above) — pending
  update.
