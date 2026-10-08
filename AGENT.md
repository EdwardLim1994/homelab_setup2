# AGENT.md

Orientation for coding agents working in this repo. Human-facing setup lives in
`README.md`; this file is about *how the pieces fit* and *where things stand*.

## What this is

A self-hosted homelab that runs on a local **k3d** cluster. One Authentik SSO
in front of everything, every app reachable over Tailscale MagicDNS
(`https://<app>.<tailnet>.ts.net`) and on the LAN (`https://<app>.local`).

Apps: Authentik, GitLab (+ runner), MinIO, n8n, SonarQube, Nextcloud, ArgoCD,
an LGTM observability stack, LiteLLM, OpenWebUI, Kafbat Kafka UI (views
sit/uat/production's kafka — see "Kafka UI" below), Harbor (container
registry — see "Harbor" below), Kaneo (ticket tracker — see
"Kaneo" below), a set of MCP servers, and an in-cluster coding-agent
stack (`omp` / oh-my-pi).

## Deploy path

**Terraform (OpenTofu)** — `terraform/internal/<app>.tf` per app, deliberate
"real" deploy, no reload. The only deploy path.

Terraform reads `terraform/<env>/local.auto.tfvars`, regenerated from the
root `.env` by `scripts/{linux,windows}/gen-tfvars.*` (gitignored, never
hand-edit).

### Secret substitution convention

`helm/<app>/values.yaml` contains `__PLACEHOLDER__` tokens. Terraform swaps
them via a `replace(replace(... file(values.yaml) ...))` chain in the app's
`.tf`. Non-secret dev defaults live inline in `values.yaml`. `set_sensitive`
in the `.tf` is used for values that must not appear in plan output.

### Authentik provisioning

`terraform/internal/authentik.tf` has two `null_resource` provisioners that create
config no `helm_release` owns:

- `authentik_app_providers` — runs `helm/authentik/provision-app-providers.py`
  to create every app's OAuth2/SAML provider inside Authentik. Without it,
  every "Log in with Authentik" button 404s.
- `authentik_github_source` — GitHub as a login source for Authentik's own
  admin panel.

Both re-run on `triggers` when their secrets or the Python script change.

### Phase-cluster platform infra

`terraform/{sit,uat,production}/` — one Terraform root module (own state)
per phase k3d cluster, each a thin `providers.tf`/`variables.tf`/`main.tf`
calling the shared `terraform/modules/platform-apps` module. Deploys
Authentik, Traefik, Unleash, Vault, Kafka, Meilisearch, MinIO, and Apicurio
Registry — same local `helm/<app>` wrapper-chart convention as the internal
cluster (`Chart.yaml` dependency on the upstream chart, `values.yaml` /
`values-phase.yaml` for defaults, terraform swaps secrets in via
`set_sensitive`). Authentik and MinIO reuse the same `helm/authentik` /
`helm/minio` chart dirs as internal, via a second `values-phase.yaml` in
each (bundled postgresql/redis subcharts, no OIDC/tailscale/homelab-CA
wiring — these clusters have none of that). This is the platform checklist
`helm/omp/roles/solution-architect/SKILL.md` tells agent pods to plan
against for every new project — these apps exist so a pod's generated
project actually has something to integrate with in SIT/UAT/production.
Phase clusters have k3s's bundled traefik disabled at cluster creation
(`create-cluster.sh --k3s-arg disable=traefik`) so `helm/traefik` owns
ports 80/443 instead — `internal` is untouched, still on k3s's own.

### OpenCost (all 4 clusters)

`helm/opencost` (local wrapper: `opencost/opencost` upstream, aliased `oc` —
its own values.yaml nests almost everything under an internal `opencost:`
key too, so without the alias every `--set`/`set{}` path here would collide
with the dependency's own name and silently no-op) deployed on `internal`
(`terraform/internal/opencost.tf`) and each phase cluster
(`terraform/modules/platform-apps/opencost.tf`). Replaced kubecost — opencost
has no UI worth exposing (its own is disabled, `oc.opencost.ui.enabled:
false`) and no auth of its own to set up; cost data surfaces entirely through
a Grafana dashboard instead
(`helm/observability/dashboards/opencost.json`, grafana.com id 22208, adapted
to the fixed `mimir` datasource + a `cluster_id` filter variable every query
now carries — same convention every other dashboard in this repo uses).

opencost itself doesn't scrape anything — it only *queries* an existing
Prometheus for kube-state-metrics/cadvisor data and computes cost from it
(`oc.opencost.prometheus.external.url`). `internal` already has a Prometheus
doing that scrape (helm/observability's bundled kube-prometheus stack), so
`internal`'s opencost just points at Mimir's Prometheus-compatible
query-frontend endpoint
(`observability-mimir-query-frontend.observability.svc.cluster.local:8080/prometheus`)
— no bundled Prometheus needed there. The phase clusters have no Prometheus
of their own, so `helm/opencost`'s second dependency (`prometheus`, same
chart/version `helm/observability` pins, gated by a `prometheus.enabled`
Chart.yaml condition) turns on there instead — kube-state-metrics +
node-exporter enabled, `remoteWrite`s into internal's Mimir the same
`host.docker.internal` NodePort bridge pattern the Harbor registry mirror
uses (`terraform/internal/observability.tf`'s `mimir_distributor_nodeport`
Service is the in-cluster half, `create-cluster.sh`'s `MIMIR_PUSH_PORT`,
default 30510, is the host half), each stamped with an
`external_labels.cluster_id` (`internal`/`sit`/`uat`/`production`, `internal`
set directly on helm/observability's own Prometheus for consistency) so the
opencost dashboard's cluster picker can tell all 4 apart.

`gen-tfvars.*` fans the same `.env` out to all four `terraform/<env>/`
dirs, filtered per-dir to the `TF_VAR_*` names each one actually declares.

### Log & trace shipper (phase clusters → internal's Loki/Tempo)

`helm/log-shipper` (local wrapper, `grafana/alloy` upstream — same chart
version `helm/observability` pins for its own Alloy) deployed on each phase
cluster (`terraform/modules/platform-apps/log-shipper.tf`) so generated
apps' pod logs and OTLP traces land in internal's Grafana/Loki/Tempo,
letting QA/dev roles link a Loki query or a trace as MR proof (see role
SKILL.md files). Two `host.docker.internal` NodePort bridges, same direction
as opencost→Mimir:

- **Logs**: automatic, no app code needed — this Alloy scrapes every pod's
  stdout on its own cluster (same discovery.kubernetes + loki.source.kubernetes
  config as `helm/observability`'s own Alloy) and pushes to
  `terraform/internal/observability.tf`'s `loki_nodeport` Service
  (`create-cluster.sh`'s `LOKI_PUSH_PORT`, default 30511).
- **Traces**: apps push OTLP to this Alloy's own in-cluster Service
  (`log-shipper-alloy.log-shipper.svc.cluster.local:4317`/`:4318`, same OTLP
  receiver pattern `helm/observability`'s Alloy exposes for internal), which
  forwards to `observability.tf`'s `tempo_nodeport` Service
  (`TEMPO_PUSH_PORT`, default 30512). Requires app-side OpenTelemetry SDK
  instrumentation — see backend-developer/SKILL.md's "Observability and
  traceability".

Every pod's logs and every span get a `cluster_id` label/attribute
(`sit`/`uat`/`production`) so Grafana can tell clusters apart, same
convention opencost's `external_labels.cluster_id` already established for
metrics. `LOKI_PUSH_PORT`/`TEMPO_PUSH_PORT` are baked in at cluster
**creation** time like `MIMIR_PUSH_PORT` — an already-running phase cluster
needs recreating to pick up a first-time addition of either.

### Kafka UI (internal, views sit/uat/production)

`helm/kafka-ui` (local wrapper, `kafbat/kafka-ui` upstream) deployed only on
`internal` (`terraform/internal/kafka-ui.tf`), Authentik SSO like every other
tailnet app. It has no kafka of its own to browse — internal doesn't run
kafka — its three `kafka.clusters[]` entries all point at phase-cluster
brokers. Same `host.docker.internal` NodePort bridge as kubecost, but the
other direction: each phase cluster exposes ITS OWN kafka via a `kafka-
external` NodePort Service (`terraform/modules/platform-apps/kafka.tf`)
mapped on **its own** k3d loadbalancer (`create-cluster.sh`'s
`KAFKA_NODEPORT`, one distinct host port per cluster — 30901/30902/30903 for
sit/uat/production, since all three share the same Docker host) — internal's
kafka-ui pod dials `host.docker.internal:<that cluster's port>`.

### Apicurio schema push (GitLab CI, per phase cluster)

Each phase cluster's Apicurio Registry (`terraform/modules/platform-apps/apicurio.tf`,
enabled by default) gets the same reversed `host.docker.internal` NodePort
bridge as Kafka above: an `apicurio-external` NodePort Service, one distinct
host port per cluster (`create-cluster.sh`'s `APICURIO_NODEPORT` —
30911/30912/30913 for sit/uat/production), since GitLab's CI runner lives
on `internal` and has no route to a phase cluster's in-cluster Service.
`APICURIO_URL_SIT`/`_UAT`/`_PRODUCTION` (`http://host.docker.internal:<port>`)
are group-level CI/CD variables set by `gitlab-webhook.yml`, inherited by
every project automatically — same convention as `HARBOR_USER`/`_PASSWORD`.

Data Engineer authors schemas under a project's `schemas/api/proto`,
`schemas/api/graphql`, `schemas/kafka` (see `data-engineer/SKILL.md`) and
just commits them — the actual registry push is a GitLab CI stage DevOps
Engineer wires (`schema-registry` stage, `push-schemas:sit/uat/production`
jobs, see `devops-engineer/SKILL.md`'s `.gitlab-ci.yml` template), gated
per environment: SIT mirrors the existing `build` job's `us/*`/`release/*`
branch rule; UAT/production trigger off the same `env/<env>/**/values.yaml`
commits that already promote app images there (`/uat`'s pre-deploy step,
the promote→main MR) — no separate flow-triggered pipeline needed.

### Harbor (internal, container registry — replaces gitlab-registry)

`helm/harbor` (local wrapper, `goharbor/harbor` upstream) deployed only on
`internal` (`terraform/internal/harbor.tf`), shared postgres/redis (DB 2)
like every other migrated app, Authentik SSO via a `null_resource` provisioner
(`oidc_verify_cert: false` — Harbor's OIDC is auto-discovery-only, so its
server-side token/userinfo calls land on Authentik's external tailnet URL,
routed in-cluster by `coredns.tf`'s split-horizon rewrite; skipping cert
verification for that one hop is simpler than a CA-bundle mount for a
homelab). `expose.type: clusterIP` — no chart-owned Ingress; both the
tailnet and `.local` ingresses are plain `kubectl_manifest` resources in
`harbor.tf` pointing at the chart's single unified `harbor` Service
(portal+core+registry all proxied through it). Every generated app's CI
pipeline pushes to `harbor.harbor.svc.cluster.local:80/library/<group>/
<project>/<app>` (F-01/F-02 prompts) using `$HARBOR_USER`/`$HARBOR_PASSWORD`
— group-level CI/CD variables on `sdlc` set by `gitlab-webhook.yml`, since
Harbor isn't GitLab's own registry and gets none of the `$CI_REGISTRY_*`
auto-vars for free. `admin` / `var.harbor_admin_password` is reused for CI
push, ArgoCD Image Updater, and Harbor's own admin login — no separate robot
account, homelab-scoped. `create-cluster.sh`'s phase-cluster containerd
mirror also points here now (was gitlab-registry) — see Known issues below,
this only takes effect on a freshly-created phase cluster.

### Apollo Router chart (internal → phase clusters, per-project GraphQL gateway)

`helm/apollo-router` is centrally-maintained infra, not a deployed release
of its own on `internal` — `terraform/internal/apollo-router-chart.tf`
packages it and pushes it as an OCI artifact to Harbor's `library/charts`
project (Harbor's default project, already exists, same one every image
push already targets) whenever the chart changes. Every generated project
gets its own router **instance** per (project, env) on the phase clusters,
provisioned by the devops-engineer agent pod at `/kickoff` — see
devops-engineer/SKILL.md's "Apollo Router Provisioning" for the full
ArgoCD multi-source Application shape (chart from Harbor OCI, values from
the project's own repo) and devops-engineer's `.gitlab-ci.yml`
`compose-supergraph` stage for how the composed supergraph schema gets kept
in sync (`rover supergraph compose` over every backend subgraph, written
into the project's own `env/{env}/apollo-router/values.yaml`, ArgoCD
auto-syncs from there). The chart itself is deliberately never copied into
any generated project's repo — one chart, many independent instances,
same "shared source, per-consumer instance" shape `terraform/{sit,uat,production}`
already uses for `platform-apps`, just keyed by project instead of by
phase-cluster. Push uses a `kubectl port-forward` to Harbor for the
duration of the push (host can't resolve `harbor.harbor.svc.cluster.local`)
— phase clusters' ArgoCD instances instead pull the chart via the same
`host.docker.internal:$REGISTRY_MIRROR_PORT` NodePort bridge every image
pull from those clusters already uses.

### Kaneo (internal, ticket tracker — replaces Taiga; wiki moved to GitLab)

`helm/kaneo` — hand-rolled (Kaneo's own chart lives inside its upstream
monorepo, not published to a repo/OCI registry), deployed only on
`internal` (`terraform/internal/kaneo.tf`). Replaces **Taiga** — Taiga's
seven-service footprint (its own RabbitMQ, a custom `taiga-contrib-oidc-auth`
plugin of unverified long-term health) was heavier than this homelab needs.
Kaneo is MIT, a single container, has native OIDC, and — the deciding
factor — a real **bidirectional** GitLab integration (task↔issue/MR sync +
webhooks, merged upstream 2026-09-26), a strict upgrade over Taiga's
one-way compliance webhook. Kaneo has **no wiki module at all**, so wiki
pages move back onto **GitLab's own per-project wiki** instead (this
reverses the "wiki moved to Taiga" call from the OpenProject→Taiga
migration, for the opposite reason: that move happened *because* Taiga had
a wiki OpenProject didn't gate behind a license; this one happens because
Kaneo doesn't have one at all).

One container (`ghcr.io/usekaneo/kaneo`), shared postgres for its DB,
shared MinIO for S3 attachment storage, no bundled Redis (optional
pub/sub-only at this scale, skipped — add `REDIS_URL` later only if Kaneo
genuinely refuses to boot without one). `ingress.enabled: false` in the
chart — same convention as Harbor/Taiga: `.local` ingress is a plain
`kubectl_manifest`, tailnet ingress comes from `locals.tf`'s
`tailscale_apps` map. OIDC uses explicit split endpoints (external tailnet
URL for the browser redirect, in-cluster `authentik-server.authentik.svc`
for server-side calls) — same convention as GitLab/Grafana/LiteLLM, so it
doesn't depend on `terraform/internal/coredns.tf`'s split-horizon rewrite
the way Harbor/MinIO's single-discovery-URL approach needs to.

n8n and omp pods talk to it over its REST API with a bearer token
(`KANEO_TOKEN`/`KANEO_URL`/`KANEO_PROJECT_ID` env vars — see `.env.example`'s
`TF_VAR_kaneo_api_token`, bootstrap-once via the browser like
`openwebui_api_key`) via a dedicated hand-rolled MCP server
(`helm/mcp-servers/kaneo-mcp`, mirrors the old `taiga-mcp` exactly — 4
generic REST tools, no maintained Kaneo MCP integration exists that fits a
headless batch Job; Kaneo's own native MCP endpoint wants an
OAuth-resolvable bearer with dynamic client registration, built for
interactive clients). Unlike `taiga-mcp`, `kaneo-mcp` holds **no credential
of its own** — it forwards whatever bearer the caller sends straight
through to Kaneo's API, so each role's own real per-role API key (see
"Real per-role Authentik/GitLab/Kaneo identities" below) is the identity on
every call, not a shared service account. See AGENTS.md's "Ticket & MR
Conventions" for the full endpoint/field mapping — Kaneo has a single
`task` resource (workspace → project → task), unlike Taiga's four separate
epic/userstory/task/issue resources.

GitLab itself is untouched — it stays the source-control + CI +
webhook-trigger system (F-00's router, `glab`/git clone for code), and now
**also hosts wiki pages again** (Architecture/PRD/Estimate, via its own
`POST /projects/:id/wikis` REST API) since Kaneo has nothing to move them
to. Kaneo's native GitLab integration (configured per-project at kickoff)
handles the compliance-trail requirement that drove Taiga's one-way webhook
in the first place — and does it better, since it's bidirectional.

#### Real per-role Authentik/GitLab/Kaneo identities

Every SDLC role (`helm/omp/values.yaml`'s `roles:` list) gets a real
Authentik user (`helm/authentik/provision-app-providers.py`'s per-role
loop, `get_or_create` on every `tofu apply`), a real GitLab user + personal
access token, and a real Kaneo user + API key (both minted by
`helm/ansible/playbooks/role-accounts.yml`, into Secrets
`omp-role-gitlab-tokens` / `omp-role-kaneo-tokens` in namespace `sdlc`).
The Authentik account exists for a human to SSO-login *as* a role for
debugging/audit (same identity name across all three systems); it is
**not** how agent pods authenticate — headless git/API operations still use
the static PAT/API key, same split GitLab's own OIDC-login-vs-PAT already
had before this change. Kaneo's admin endpoints are gated by a session
cookie (Better Auth), not pod-exec like Taiga's old `manage.py shell`
approach — `role-accounts.yml`'s Kaneo section signs in as the bootstrap
admin, creates each role's user, impersonates them, and mints an API key
under that impersonated session, all as normal in-cluster HTTP (no new
RBAC needed for this, unlike Taiga's `ansible_taiga_exec` Role which this
replaces nothing for).

Not cleaned up automatically from the Taiga removal (same class of leftover
every prior app swap in this repo has left, see Known issues below):
Authentik's `Taiga` OAuth2Provider/Application still sits in its DB (the
provisioner only creates/updates, never deletes); the shared-postgres
`taiga` role/db and any PVCs it had aren't dropped either.

## Repo layout

```
helm/<app>/            Helm chart
helm/<app>/values.yaml Chart values with __PLACEHOLDER__ secret tokens
terraform/internal/<app>.tf     Matching Terraform resource
terraform/internal/locals.tf    app_url map, authentik_url, shared locals
terraform/internal/variables.tf All TF_VAR_* inputs + dev defaults
terraform/modules/platform-apps/  shared module: authentik/unleash/vault/kafka/
                       meilisearch/minio/apicurio, instantiated by sit/uat/production
terraform/{sit,uat,production}/  thin root module per phase cluster (own state)
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

Each consumer's `.tf` has `depends_on = [helm_release.postgres(, .redis)]`.
**nextcloud keeps its own
MariaDB** (different engine); **argocd keeps its bundled redis** (tightly
coupled to the argo-cd subchart). Old per-app `<app>-postgres` /
`<app>-redis` templates are gone — after switching, orphan
`data-<app>-postgres-0` PVCs must be deleted by hand (StatefulSet PVCs aren't
pruned).

## Tailscale ingress

`terraform/internal/tailscale.tf` (operator) + `terraform/internal/tailscale-ingress.tf` (one
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

**Split-horizon DNS** (`terraform/internal/coredns.tf`): pods can't route to the Tailscale
Service VIP, so an app doing OIDC discovery server-side against
`https://authentik.<tailnet>` just times out. A `coredns-custom` rewrite points
that name at traefik in-cluster + a traefik vhost serves it with a homelab-CA
cert; the consuming app trusts that CA (minio via the chart's
`trustedCertsSecret`, openwebui via an init container). Browser traffic is
untouched. Apps that *can* split browser vs backend endpoints
(gitlab/grafana/litellm) skip all this and just
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
  proxy so LiteLLM can list the omp pods as models. (It only wakes — never
  scales back down; `helm/mermaid-render` below does both directions.)
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
(`terraform/internal/ansible.tf`, built from the files — not the helm chart).

`seed.sh` strips read-only keys (`active`, `tags`) before `POST /api/v1/workflows`
and activates via `POST /workflows/{id}/activate` (n8n 2.x).

**`/plan_release` (F-01) is report-only — it makes zero GitLab/Kaneo
writes.** Architect/DE/QA/Security/UX/PM/Tech-Lead each write their
section to a local markdown file and `mc cp` it to
`release-reports/<version>/<section>.md` in MinIO (the plan_release <->
kickoff hand-off store — `helm/minio/values.yaml`'s `buckets:` list; `mc`
and `pandoc` are baked into the omp image, `helm/omp/Dockerfile`; MinIO
creds reach the role pod as `$MINIO_ENDPOINT`/`$MINIO_ROOT_USER`/
`$MINIO_ROOT_PASSWORD`, same plain-env/`set_sensitive` split as
`$KANEO_URL`/`$KANEO_TOKEN` — see `helm/n8n/values.yaml` +
`terraform/internal/n8n.tf`). A final PM step downloads all seven
sections, concatenates them, and `pandoc`s the result into
`release-reports/<version>/development-plan.docx` — pull it via the MinIO
console (no presign tooling exists in this repo). Architecture diagrams are
rendered to real PNGs before the PDF is built — see "mermaid-render" below
— and referenced via standard markdown image syntax, not left as raw
` ```mermaid ` fences (pandoc has no Mermaid renderer on its own).

**`/kickoff` (F-02) is where everything actually gets created** — GitLab
group/project (+ owner membership), the nx workspace scaffold + CI/
Dockerfile/registry wiring committed to `main`, the three wiki pages
(Architecture/PRD/Estimate — published to **GitLab's own** per-project
wiki, fetched back from MinIO's `release-reports/<version>/*.md`), the
GitLab milestone, Kaneo's native GitLab integration wired to this project,
then Kaneo tasks for every QA/Security/DevOps work item, the release
branch, and the story/task branches — in that order, since branches fork
from `main` and `main` must be scaffolded first.

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

Playbooks: `n8n.yml`, `mcp-servers.yml`, `omp.yml`, `litellm.yml`,
`openwebui.yml`. With no argument the script launches one Job per playbook,
all in parallel (no cross-dependencies now that `mattermost.yml` — the one
thing chained after n8n — is gone). Pass `site` to run the old serial
`site.yml` in a single Job instead. Runner SA is
`ansible-runner`; per-namespace Roles for it live in `terraform/internal/ansible.tf`.

`openwebui.yml` installs `helm/ansible/pipe/sdlc_pipe.py` as an OpenWebUI
Function via the admin API (create-or-update, idempotent, enables it if not
active) — needs `TF_VAR_openwebui_api_key`, a personal API key generated
once via the browser (OpenWebUI is SSO-only, so unlike n8n.yml this can't
script a login). `n8n.yml` similarly needs `TF_VAR_n8n_mcp_api_key`, but that
one bootstraps itself — leave it blank the first run, the playbook mints a
key and prints it, paste it back into `.env` so later runs reuse it instead
of minting a new one every time (n8n only ever returns the raw key once).
Full generation steps for both: README.md's env-var table.

`gitlab-webhook.yml` (+ `gitlab-webhook-project.yml`, included per-project) is
**not** in `site.yml` — bootstrap / disaster-recovery for the n8n SDLC webhook
that feeds flow F-00. Registers a **project-level** hook on every project in the
`sdlc` group (group hooks are Premium; this GitLab is CE) — idempotent, creates
the `sdlc` group if missing. `scripts/ansible-run.{sh,ps1} gitlab-webhook`.
Needs no PAT in `.env` — mints a fresh `sdlc-webhook` api token via `rails
runner` in the webservice pod (needs `pods/exec` in `gitlab`, see
`terraform/internal/ansible.tf`). Uses `gitlab_webhook_secret` from `ansible-secrets`.
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
scripts/linux/gen-tfvars.sh && (cd terraform/internal && tofu apply)   # deploy
scripts/linux/list-urls.sh                        # app URLs + status
scripts/linux/restore-postgres-backup.sh --list   # list/restore shared-postgres backups (destructive)
scripts/linux/omp-shell.sh                        # interactive omp pod shell
scripts/linux/ansible-run.sh                      # every playbook, parallel fan-out
scripts/linux/ansible-run.sh <playbook>           # just one (n8n / omp / litellm / …)
scripts/linux/ansible-run.sh gitlab-webhook       # not in the default set
kubectl -n omp scale deploy/omp --replicas=1      # wake the agent pod
```

## Current progress

Working and verified end-to-end:

- Full cluster deploys via Terraform.
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
- **`helm/mermaid-render`** — scale-to-zero `mermaid-cli` (`mmdc`) HTTP
  microservice (`minlag/mermaid-cli` image, `server.js` wrapper mounted via
  ConfigMap, same convention as `omp-adapter`'s `server.py`), namespace
  `sdlc`. `helm/omp/scripts/render-mermaid.sh` (baked into `omp-box:dev`)
  PATCHes its `/scale` subresource to wake it, POSTs Mermaid source to
  `/render`, saves the PNG, then scales it back to 0 itself in a trap —
  unlike `omp-adapter`'s waker, which never scales down. Used by
  `/plan_release`'s architect + PM steps so the final PDF embeds real
  diagram images instead of raw ` ```mermaid ` text. Verified live:
  scale 0→1→0, real PNG rendered and confirmed visually.
- **OpenWebUI** — SSO-only login (Authentik), routed through LiteLLM, PWA
  install verified working.
- **MCP servers** — grafana, sonarqube, gitlab, playwright, **n8n**
  (`czlonkowski/n8n-mcp`, docs + management once `n8n.yml` injects the key),
  **kaneo** (hand-rolled, Kaneo's own native MCP wants an
  OAuth-resolvable bearer — awkward for a batch Job — `helm/mcp-servers/kaneo-mcp/`,
  4 generic REST tools — `kaneo_get`/`_post`/`_patch`/`_delete` — over
  Kaneo's API rather than one bespoke tool per resource type, since
  AGENTS.md's endpoint table already covers that and would need mirroring
  forever otherwise. No credential of its own — forwards whatever bearer
  the caller sends straight to Kaneo, so each role's real per-role API key
  is the identity on every call. Registered in LiteLLM's `mcp_servers` like
  the others, and wired directly into every omp-agent Job via
  `--mcp-config` (F-31's `Build Job Manifest` node) — this is the only
  in-house-built one in the set).
- **GitLab webhook** — `gitlab-webhook.yml` registers a project-level SDLC
  hook on every project in the `sdlc` group (CE has no group hooks).

Known issues / next steps:

- **OpenProject → Taiga swap left orphans**, same class of leftover
  Mattermost's removal did (see below): the `openproject` OAuth2Provider/
  Application in Authentik's DB, the shared-postgres `openproject` role/db,
  and `helm/openproject`'s old PVCs (if the release ever fully came up)
  aren't dropped automatically — the provisioner only creates/updates,
  `helm/postgres`'s initdb only runs once, and `helm uninstall` doesn't
  touch cluster-external state. Remove by hand if it matters.
- **Taiga → Kaneo swap left orphans**, same class of leftover as the
  OpenProject/Mattermost removals above: Authentik's `Taiga`
  OAuth2Provider/Application, the shared-postgres `taiga` role/db, and its
  PVCs aren't dropped automatically. Remove by hand if it matters.
- Kaneo's admin-session-cookie provisioning in `role-accounts.yml`
  (sign-in → create-user → impersonate → create-API-key) follows Better
  Auth's documented plugin conventions but hasn't been live-verified
  against Kaneo's pinned image version — run it once by hand for a single
  role before trusting it for all 12; fall back to manual per-role browser
  bootstrap (same tier of step `openwebui_api_key` already needs) if it
  doesn't pan out.

- **Harbor migration is script-only for phase clusters.** `create-cluster.sh`
  now bakes the containerd mirror config for a Harbor NodePort, but the
  mirror config is set at cluster **creation** time — the live sit/uat/
  production k3d clusters still have the old gitlab-registry mirror baked
  in and won't pick this up until they're recreated (deliberately not done
  as part of this migration — nothing currently exercises that pull path
  end-to-end). GitLab's own bundled registry is untouched and still running,
  just no longer referenced by any prompt/config.

- The omp base Deployment idles at `replicas: 0`; first chat after idle waits
  ~1–2 min. Ollama must be running on the host or nothing LLM-shaped works.
- `seed.sh` bails if any workflow exists unless `--force`, and `--force`
  creates duplicates — not a true upsert. Wipe + reseed is the working path.
- Old per-app `data-<app>-postgres-0` / `-postgresql-0` PVCs are orphaned after
  the shared-DB switch — delete them by hand (StatefulSet PVCs aren't pruned).
- `opencode` fully removed (`omp`). `openwebui` was removed in favor of
  Mattermost, then restored (`helm/openwebui`, `terraform/internal/openwebui.tf`) as a
  SSO-only chat UI onto the same LiteLLM backend. OpenWebUI is a PWA out of
  the box (own manifest/service worker); no extra server config beyond the
  HTTPS it already gets from the Tailscale/LAN ingress — install via the
  browser's "Add to Home Screen" (iOS: Safari only) / install icon (desktop
  Chrome/Edge). Login is SSO-only (`ENABLE_LOGIN_FORM: "False"`) — no
  password form.
- **Mattermost removed** (superseded by OpenWebUI for chat — see above). Live
  cluster resources torn down via `tofu destroy`; `helm/mattermost/` and
  `terraform/internal/mattermost.tf` deleted; its shared-postgres db entry, MinIO
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
