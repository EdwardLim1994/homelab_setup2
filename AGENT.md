# AGENT.md

Orientation for coding agents working in this repo. Human-facing setup lives in
`README.md`; this file is about *how the pieces fit* and *where things stand*.

## What this is

A self-hosted homelab that runs on a local **k3d** cluster. One Authentik SSO
in front of everything, every app reachable over Tailscale MagicDNS
(`https://<app>.<tailnet>.ts.net`) and on the LAN (`https://<app>.local`).

Apps: Authentik, GitLab (+ runner), MinIO, n8n, SonarQube, Nextcloud, ArgoCD,
an LGTM observability stack, Mattermost, LiteLLM, a set of MCP servers, and an
in-cluster coding-agent stack (`omp` / oh-my-pi).

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
```

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

`helm/ansible/flows/F-*.json` — 29 n8n workflows implementing an SDLC pipeline
driven by Mattermost slash commands + GitLab/CI webhooks. Seeded by
`helm/ansible/flows/seed.sh`, run from `helm/ansible/playbooks/n8n.yml`
(mints an n8n API key, then upserts the flows). Flow files are mounted at
`/flows` in the ansible runner via the `ansible-n8n-flows` ConfigMap
(`terraform/ansible.tf`, built from the files — not the helm chart).

`seed.sh` strips read-only keys (`active`, `tags`) before `POST /api/v1/workflows`
and activates via `POST /workflows/{id}/activate` (n8n 2.x).

## Mattermost

- Team Edition image. SSO via Mattermost's **GitLab-format OAuth slot pointed
  at Authentik** (TE has no generic OIDC) — login button says "GitLab", goes
  to Authentik. `provision-app-providers.py` adds a numeric-`id` claim mapping
  that Mattermost's driver needs.
- **File storage → MinIO S3** (`MM_FILESETTINGS_*` in `values.yaml`, bucket
  `mattermost` pre-created by `helm/minio`, MinIO root creds, plain http on
  the in-cluster endpoint — same pattern GitLab uses).
- Mobile push via the hosted test gateway (`push-test.mattermost.com`).
- **`playbooks/mattermost.yml`** automates the chat integration: `mmctl --local`
  (root socket, no auth — works around OIDC-only login) creates the `ai`
  channel + `sdlc-svc` user + a personal access token + the outgoing webhook
  (`omp` trigger word → n8n `/webhook/mm-chat`), then registers the token as
  an n8n `mattermostApi` credential and runs `bind-mm-cred.py` to point all
  Mattermost-using flows at it. Needs `MM_SERVICESETTINGS_ENABLELOCALMODE`,
  `ENABLEOUTGOINGWEBHOOKS`, `ENABLEUSERACCESSTOKENS` (all in `values.yaml`)
  and the `pods/exec` RBAC in `terraform/ansible.tf`.
- **Two ways to chat with the agent:**
  1. `F-28-chat.json` — type `omp <question>` in `#ai`; the outgoing webhook
     hits n8n → LiteLLM `omp` model → reply posted back.
  2. The **Agents** plugin (`mattermost-ai`, already installed + enabled) —
     configure a bot in System Console → Plugins → Agents pointed at
     `http://litellm.litellm.svc.cluster.local:4000/v1` with the LiteLLM
     master key and model `omp` (agent) or `qwen3.8:27b` (plain chat). This
     is the "chat like a normal user" path (DMs, @mentions, streaming).

## Ansible runner

`helm/ansible/` renders a **permanently-suspended CronJob**. Playbooks run as
one-shot Jobs cloned from it by `scripts/{linux,windows}/ansible-run.*`:

```
scripts/linux/ansible-run.sh              # playbooks/site.yml (everything)
scripts/linux/ansible-run.sh n8n          # playbooks/n8n.yml
scripts/linux/ansible-run.sh mattermost --syntax-check
```

Playbooks: `n8n.yml`, `mattermost.yml`, `mcp-servers.yml`, `omp.yml`,
`litellm.yml`, chained by `site.yml`. Runner SA is `ansible-runner`; per-namespace
Roles for it live in `terraform/ansible.tf`.

## Conventions

- **`ponytail:` comments** mark deliberate simplifications and their upgrade
  path. Respect them; don't "fix" them without cause.
- **`mmctl --local`** is `/mattermost/bin/mmctl --local` inside the pod; it
  hits a root Unix socket, no auth. `bot create` is **not** available in
  local mode (hence `sdlc-svc` is a normal user).
- **`kubernetes.core.k8s_exec`** returns `return_code`/`stdout`, not `rc`.
- k3d image flow: build `k3d-registry:5111/omp-box:dev` (or `localhost:5111/...`),
  push, `crictl rmi` the old tag on the node so `IfNotPresent` re-pulls.
- Git Bash mangles `/mattermost/...` args to `kubectl exec` — prefix with
  `MSYS_NO_PATHCONV=1`.

## Common commands

```bash
scripts/linux/create-cluster.sh              # one-time k3d cluster
scripts/linux/dev-up.sh                       # tilt up (dev path)
scripts/linux/gen-tfvars.sh && (cd terraform && tofu apply)   # prod path
scripts/linux/list-urls.sh                     # app URLs + status
scripts/linux/omp-shell.sh                      # interactive omp pod shell
scripts/linux/ansible-run.sh <playbook>          # post-deploy playbooks
kubectl -n omp scale deploy/omp --replicas=1       # wake the agent pod
```

## Current progress

Working and verified end-to-end:

- Full cluster deploys via both Tilt and Terraform.
- Authentik SSO for every app; Tailscale + LAN ingress.
- **omp agent stack** — `models.yml` fixed for omp 18.x (`baseUrl` without
  `/v1`, `auth: none`); default model is `ollama/qwen3.8:27b` (the 80B
  `qwen3-coder-next` OOMs on the host); `pod-openai.py` runs `omp models
  refresh` at boot and pins `--model`. `n8n → LiteLLM omp → omp-adapter →
  omp pod → Ollama` returns completions.
- **29 n8n SDLC flows** seeded and active. Flow JSONs had stale `Slack:`
  connection refs (renamed to `Mattermost:` in nodes but not connections) —
  fixed. `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` set so flows' `$env.*`
  expressions resolve.
- **Mattermost** — SSO, MinIO S3 file storage, mobile push, and the
  `mattermost.yml` automation (bot user, `#ai` channel, outgoing webhook,
  n8n credential, flow binding). `F-28` chat verified: `omp <q>` in `#ai`
  posts an omp reply.
- **codegraph index** cleaned (was holding deleted `openwebui` paths).

Known issues / next steps:

- The omp base Deployment idles at `replicas: 0`; first chat after idle waits
  ~1–2 min (pod scale-up + 27B model load on CPU). Ollama must be running on
  the host or nothing LLM-shaped works.
- `seed.sh` bails if any workflow exists unless `--force`, and `--force`
  creates duplicates — not a true upsert despite the comment. Wipe +
  reseed is the working path.
- Mattermost files uploaded before the S3 switch sit on the `data` PVC and
  404; no migration done.
- The Agents-plugin bot is not scripted (custom config blob is version-
  specific) — configure via System Console UI.
- `openwebui` fully removed (replaced by Mattermost). `opencode` fully
  removed (replaced by `omp`).
