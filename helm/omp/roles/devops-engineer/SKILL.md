---
name: devops-engineer
description: DevOps Engineer agent for infrastructure provisioning, CI/CD pipeline configuration, ArgoCD setup, cluster management, and registry configuration. Use during /develop gate A (must complete before all other pods start) and when provisioning new project infrastructure. Also manages cluster lifecycle (wake/sleep) throughout the SDLC.
compatibility: omp, claude-code
license: MIT
---

# DevOps Engineer Agent

## Role

Provisions and maintains all infrastructure required for the SDLC: CI/CD pipelines, ArgoCD applications, Kubernetes clusters, container registry namespaces, and GitLab runners. Gate A: nothing can build or deploy until this pod signals ready.

## When this skill is active

- `/develop` gate A — first pod to run, blocks everything else
- `/kickoff` — provisioning new project infrastructure (new projects only), creating one DevOps ticket per story issue
- Cluster lifecycle management — called by n8n throughout SDLC phases

---

## DevOps Ticket Creation (at `/kickoff`)

One DevOps ticket per story issue — self-created, not created by Tech Lead
(Tech Lead's task tickets are scoped to backend/frontend/api only). Covers
infra work the story needs beyond the one-time project provisioning below
(new env vars, a new platform-infra dependency, etc.) — most stories need no
DevOps work at all beyond what's already provisioned; create the ticket
anyway so it's visible as "none needed" rather than silently absent.

```bash
op_status_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/task-statuses?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="Pending") | .id')
me=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/users" | jq -r '.[] | select(.username=="devops-engineer") | .id')
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X POST "$TAIGA_URL/api/v1/tasks" \
  -H "Content-Type: application/json" \
  -d "{\"project\": $TAIGA_PROJECT_ID,
       \"subject\": \"[devops] {story short description} — infra checklist\",
       \"description\": \"{the concrete infra items this story needs beyond what /kickoff already provisioned, or \\\"None beyond standard provisioning\\\"}\",
       \"assigned_to\": $me,
       \"status\": $op_status_id,
       \"user_story\": {story-N},
       \"tags\": [\"v{X}.{Y}.{Z}\"]}"
# Parented to the story via user_story (same hierarchy pattern as task tickets)
```

---

## Gate A — Development Infra Readiness Checklist

Before signalling ready, verify ALL of the following:

```bash
# 1. Harbor registry reachable (not GitLab's own bundled registry — this
#    homelab's images all live in Harbor, see AGENT.md's "Harbor" section)
curl -u "$HARBOR_USER:$HARBOR_PASSWORD" \
  "http://harbor.harbor.svc.cluster.local:80/api/v2.0/projects/library/repositories"

# 2. GitLab runner registered and active
glab ci list-runners --status=active

# 3. ArgoCD SIT application exists and is healthy
argocd app get {project}-sit --server $ARGOCD_URL

# 4. ArgoCD Image Updater running
kubectl get deployment argocd-image-updater -n argocd

# 5. Apicurio registry accessible (SIT — this gate runs before SIT deploy)
curl "${APICURIO_URL_SIT}/apis/registry/v2/search/artifacts"

# 6. Kafka broker reachable
kafka-topics.sh --list --bootstrap-server $KAFKA_BOOTSTRAP
```

Signal n8n when all pass: `{"status": "infra-ready", "task_id": "$TASK_ID"}`
Signal failure if any check fails: `{"status": "infra-failed", "check": "{failed check}", "task_id": "$TASK_ID"}`

---

## New Service Scaffolding

Runs at `/develop` gate A, before the infra checklist, whenever
`openspec/impl/devops.pseudo.md` flags a new deployable service (see Tech
Lead's pseudocode format). Every deployable service must have a
`Dockerfile` (under `apps/backend/{service}/` or `apps/frontend/{service}/`
— see AGENTS.md's "Generated repo structure"), a `helm/{service}` chart
(templates only, no per-env values — see below), and one
`env/{environment}/{service}/values.yaml` per environment it deploys to —
none of this exists by default for a service added mid-project.

```bash
# 1. Read the flag
grep -A5 "new deployable service" openspec/impl/devops.pseudo.md

# 2. Copy the pattern from the named existing service — resolve both
#    services' app roots via nx rather than guessing backend vs frontend
existing_root=$(nx show project {existing-service} --json | jq -r .root)
new_root="apps/$(echo "$existing_root" | cut -d/ -f2)/{new-service}"   # backend or frontend, same segment as the existing service
mkdir -p "$new_root"
cp "$existing_root/Dockerfile" "$new_root/Dockerfile"
cp -r helm/{existing-service} helm/{new-service}
# then edit: base image/runtime per pseudo.md, chart name — strip any
# environment-specific values out of helm/{new-service}/values.yaml,
# it only ever holds chart defaults now

# 3. Create the per-env values files — one per environment the service
#    deploys to (sit/uat/production at minimum)
for env in sit uat production; do
  mkdir -p env/$env/{new-service}
  cp env/$env/{existing-service}/values.yaml \
     env/$env/{new-service}/values.yaml
  # edit: image repo/tag, replicas, resource limits, env vars per environment
done

# 4. Commit alongside the task branch so the ArgoCD step (below) has a
#    chart + values to point at
git add "$new_root/Dockerfile" helm/{new-service} env/*/{new-service}
git commit -m "chore(GL-{N}): scaffold Dockerfile + helm chart + env values for {new-service}"
```

Skip entirely if devops.pseudo.md doesn't flag a new service — most tasks
touch existing services only.

### Env values convention

Every helm chart's values live outside the chart, at
`env/{environment-name}/{application-name}/values.yaml` on repo root —
`helm/{service}/values.yaml` (if present at all) holds chart defaults only,
never environment-specific data. `{environment-name}` is one of `sit`/`uat`/`production` — no separate QA or
staging cluster exists. QA-related tasks target `sit`; staging-related tasks
(promotion retag, performance tests, staging confirmation scans) target
`uat`. `{application-name}` matches the `helm/{application-name}` chart dir
name exactly. ArgoCD's `source.helm.valueFiles` (see ArgoCD Application
below) is what makes the chart actually pick these up — a chart deployed
without pointing at its `env/` file gets only chart defaults, which is a
provisioning bug, not an acceptable fallback.

---

## New Project Provisioning

### Namespace convention

Phase clusters (sit/uat/production) are multi-tenant — more than one
project can be in flight on the same cluster, so every namespace is scoped
by project, never a bare `{env}`:

```
{environment-name}-{project-name}-{service-type}-{service-name}
```

- `service-type` is `backend` or `frontend` for anything under
  `apps/backend/*`/`apps/frontend/*` (resolve via `nx show project {name}
  --json | jq -r .root`, same as the `build` stage) — never guess it from
  the service name.
- `service-type` is `infra` for per-project platform pieces DevOps
  provisions directly (Apollo Router below is the first of these) — distinct
  from cluster-shared platform infra (Kafka, Vault, Apicurio, ...), which
  lives in this homelab's own fixed namespaces, not per-project ones.

Example: story service `payments` in project `hr-portal` on SIT →
`sit-hr-portal-backend-payments`. Its Apollo Router instance →
`sit-hr-portal-infra-apollo-router`.

### GitLab CI/CD Pipeline

`.gitlab-ci.yml` base structure — ONE pipeline for the whole monorepo, not
one per app. `lint`/`test`/`build`/`container-scan` all loop over whatever
apps `nx affected` reports for this commit range (see AGENTS.md's
"Generated repo structure" — never repo-wide, never assuming a single app):

```yaml
stages:
  - secrets-scan
  - lint
  - test
  - sonarqube
  - dependency-scan
  - build
  - schema-registry
  - container-scan
  - compose-supergraph
  - notify-n8n

variables:
  DOCKER_TLS_CERTDIR: "/certs"
  DOCKER_HOST: tcp://docker:2376
  DOCKER_TLS_VERIFY: "1"
  DOCKER_CERT_PATH: "/certs/client"

# ponytail: dockerd defaults to HTTPS for every registry regardless of port —
# :80 in the image ref alone does not disable that (see AGENT.md's Harbor
# gotcha). The dind service needs --insecure-registry explicitly, or every
# push/login against harbor.harbor.svc.cluster.local:80 fails with "server
# gave HTTP response to HTTPS client". Both build and promote-and-retag use
# this service.
.dind-service: &dind-service
  services:
    - name: docker:24-dind
      command: ["--insecure-registry=harbor.harbor.svc.cluster.local:80"]

secrets-scan:
  stage: secrets-scan
  image: zricethezav/gitleaks:latest
  script:
    - gitleaks detect --source . --exit-code 1

lint:
  stage: lint
  image: oven/bun:latest
  script:
    - bun install --frozen-lockfile
    # ponytail: nx affected, not a blanket `biome ci src/` — this repo has
    # no root `src/`, every app lives under apps/backend/*|apps/frontend/*
    # (see AGENTS.md). Same rule backend/frontend-developer already follow
    # for their own local pre-MR checks — CI isn't a looser/separate rule.
    - bunx nx affected -t typecheck,lint --base=main

# ponytail: `bunx nx affected -t test` runs real Jest's source (correctly
# bun-installed) but executed BY the Bun runtime, not Node — Bun isn't 100%
# Node-compatible for jest-environment-node, causing two symptoms: (1) a
# passing suite still exits non-zero from a WritableStreamDefaultWriter
# getter TypeError during Bun's jest-util environment teardown, unrelated to
# the actual tests; (2) nx-generated e2e global-setup.ts/global-teardown.ts
# (stock boilerplate mixing `import` with `module.exports`, fine under real
# Jest's ts-jest/swc-jest CJS transform) fails under Bun's own TS transpiler
# with "Cannot use import statement with CommonJS-only features" because Bun
# auto-detects the file as ESM off the `import` then chokes on the `module.
# exports` it also contains. If this test stage starts failing on a fresh
# project for reasons that look like tooling, not test content, check
# whether `node` is available in this image and whether invoking nx via
# `node ./node_modules/.bin/nx` instead of `bunx nx` sidesteps both — bun
# only needs to be the package manager (`bun install`), not necessarily the
# runtime that executes jest. Normalizing e2e support files to pure CJS
# (`require()`, matching their `.cts` jest config) may also be needed
# regardless, since they're ambiguous either way.
test:
  stage: test
  image: oven/bun:latest
  script:
    - bun install --frozen-lockfile
    - bunx nx affected -t test --base=main -- --coverage
  coverage: '/Lines\s*:\s*(\d+\.?\d*)%/'
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

sonarqube:
  stage: sonarqube
  image: sonarsource/sonar-scanner-cli:latest
  script:
    - sonar-scanner
      -Dsonar.projectKey=${CI_PROJECT_NAME}
      -Dsonar.host.url=${SONAR_HOST_URL}
      -Dsonar.token=${SONAR_TOKEN}
      -Dsonar.qualitygate.wait=true

dependency-scan:
  stage: dependency-scan
  image: aquasec/trivy:latest
  script:
    - trivy fs --exit-code 1 --severity CRITICAL,HIGH .

build:
  stage: build
  image: docker:24-dind
  <<: *dind-service
  # ponytail: runner is already privileged with docker:dind wired — plain
  # docker build/push, not kaniko (deprecated, don't reintroduce it). One
  # image PER AFFECTED APP (nx affected --type=app), not one repo-wide
  # image — this is a monorepo with apps/backend/* + apps/frontend/*, a
  # single `docker build .` at repo root was never valid here. Tag is the
  # rc version from that app's OWN package.json (bumped by backend/frontend-
  # developer on every task merge), not the commit SHA — this is the tag QA
  # records as "tested" on the story MR, and the tag /uat's pre-deploy step
  # promotes to UAT by exact string match. A SHA tag would break that
  # traceability. Registry is Harbor, not GitLab's own bundled one (no
  # $CI_REGISTRY_* auto-vars apply here — see AGENT.md's "Harbor" section);
  # the :80 must be explicit, docker's registry client assumes https/443 for
  # a bare hostname and this is plain http.
  script:
    # docker:24-dind is Alpine-based — jq/nx's node runtime need bun, apk installs it
    - apk add --no-cache jq bun
    - bun install --frozen-lockfile
    - docker login -u "$HARBOR_USER" -p "$HARBOR_PASSWORD" harbor.harbor.svc.cluster.local:80
    - |
      for app in $(bunx nx show projects --affected --type=app --base=main); do
        root=$(bunx nx show project "$app" --json | jq -r .root)
        version=$(jq -r .version "$root/package.json")
        image="harbor.harbor.svc.cluster.local:80/library/${CI_PROJECT_PATH}/${app}"
        docker build -t "${image}:v${version}" "$root"
        docker push "${image}:v${version}"
        # ponytail: container-scan's trivy image is minimal (no bun/nx) — pass
        # the built image list forward as an artifact instead of re-deriving
        # nx-affected there.
        echo "${image}:v${version}" >> built-images.txt
      done
  artifacts:
    paths: [built-images.txt]
  rules:
    # every MERGE into a story branch (us/*) or release branch builds+pushes
    # — needed for SIT auto-deploy AND as a fallback/rollback target. A push
    # to a task/feature branch itself (pre-merge) does not build.
    - if: '$CI_PIPELINE_SOURCE == "push" && ($CI_COMMIT_REF_NAME =~ /^us\// || $CI_COMMIT_REF_NAME =~ /^release\//)'

# ponytail: data-engineer commits schema files under schemas/api/proto,
# schemas/api/graphql, schemas/kafka (see data-engineer/SKILL.md) — pushing
# them to Apicurio is CI's job, not the agent's own shell, so it can't race
# a concurrent pipeline and always runs off the committed state. One job
# per environment's Apicurio (APICURIO_URL_SIT/_UAT/_PRODUCTION — group-level
# CI/CD vars, see gitlab-webhook.yml), gated on that environment's own
# trigger surface: SIT mirrors the `build` job's branch rule; UAT/production
# fire off the same env/<env>/**/values.yaml commits that already promote
# app images there (see /uat's Pre-UAT Deploy step, /release_production's
# promote→main MR) — no separate flow-triggered pipeline needed.
.push-schemas:
  image: curlimages/curl:latest
  script:
    # curlimages/curl is busybox ash — no bash globstar, use find instead.
    - |
      find schemas/api/proto schemas/kafka -type f -name '*.proto' 2>/dev/null | while read -r f; do
        artifact_id=$(echo "$f" | sed -E 's#schemas/(api/proto|kafka)/##; s#\.proto$#-v1#; s#\.#-#g; s#/#-#g')
        curl -sf -X POST "${APICURIO_URL}/apis/registry/v2/groups/${CI_PROJECT_NAME}/artifacts" \
          -H "Content-Type: application/x-protobuf" \
          -H "X-Registry-ArtifactId: ${artifact_id}" \
          --data-binary "@${f}"
      done
      find schemas/api/graphql -type f -name '*.graphql' 2>/dev/null | while read -r f; do
        artifact_id=$(basename "$f" .graphql)-graphql-v1
        curl -sf -X POST "${APICURIO_URL}/apis/registry/v2/groups/${CI_PROJECT_NAME}/artifacts" \
          -H "Content-Type: application/graphql" \
          -H "X-Registry-ArtifactId: ${artifact_id}" \
          --data-binary "@${f}"
      done

push-schemas:sit:
  extends: .push-schemas
  stage: schema-registry
  variables:
    APICURIO_URL: $APICURIO_URL_SIT
  rules:
    # same trigger surface as `build` — SIT auto-deploys off every us/*
    # or release/* branch push.
    - if: '$CI_PIPELINE_SOURCE == "push" && ($CI_COMMIT_REF_NAME =~ /^us\// || $CI_COMMIT_REF_NAME =~ /^release\//)'

push-schemas:uat:
  extends: .push-schemas
  stage: schema-registry
  variables:
    APICURIO_URL: $APICURIO_URL_UAT
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes:
        - env/uat/**/*

push-schemas:production:
  extends: .push-schemas
  stage: schema-registry
  variables:
    APICURIO_URL: $APICURIO_URL_PRODUCTION
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes:
        - env/production/**/*

container-scan:
  stage: container-scan
  image: aquasec/trivy:latest
  needs: [build]
  script:
    # one scan per image build just produced — built-images.txt is build's
    # artifact (see its ponytail comment), never $CI_REGISTRY_IMAGE (that's
    # GitLab's own bundled registry, this repo uses Harbor instead).
    - |
      while read -r image; do
        trivy image --exit-code 1 --severity CRITICAL "$image"
      done < built-images.txt

# ponytail: recomposes the supergraph whenever ANY backend subgraph SDL
# changes (not gated on `nx affected` — federation composition is holistic,
# a change to one subgraph can break another's field ownership, always
# compose from the full current set). Writes the result straight into the
# project's own env/{env}/apollo-router/values.yaml — that's the ONLY place
# the schema lives (see helm/apollo-router's ponytail comment: no hand
# edits). ArgoCD's automated sync on the router Application picks it up from
# there, same GitOps flow every other service already uses. Requires rover
# (Apollo's CLI) — not preinstalled, curl its installer.
compose-supergraph:
  stage: compose-supergraph
  image: oven/bun:latest
  needs: [build]
  script:
    - curl -sSL https://rover.apollo.dev/nix/latest | sh
    - export PATH="$HOME/.rover/bin:$PATH"
    - apk add --no-cache yq 2>/dev/null || (apt-get update && apt-get install -y --no-install-recommends yq)
    - |
      # One entry per backend app — domain name convention: the backend
      # service's own nx project name IS the subgraph name and matches its
      # schemas/api/graphql/{domain}.graphql file. A service that owns no
      # GraphQL subgraph (pure gRPC-internal, e.g. a worker) has no matching
      # schemas/api/graphql/{name}.graphql file — skip it, don't error.
      echo "subgraphs:" > supergraph-config.yaml
      for app in $(bunx nx show projects --type=app --json | jq -r '.[]' ); do
        root=$(bunx nx show project "$app" --json | jq -r .root)
        [ "$(echo "$root" | cut -d/ -f2)" = "backend" ] || continue
        schema="schemas/api/graphql/${app}.graphql"
        [ -f "$schema" ] || continue
        ns="${CI_ENVIRONMENT_NAME}-${CI_PROJECT_NAME}-backend-${app}"
        echo "  ${app}:" >> supergraph-config.yaml
        echo "    routing_url: http://${app}.${ns}.svc.cluster.local/graphql" >> supergraph-config.yaml
        echo "    schema:" >> supergraph-config.yaml
        echo "      file: ${schema}" >> supergraph-config.yaml
      done
      echo "federation_version: =2.7.0" >> supergraph-config.yaml
    - rover supergraph compose --config supergraph-config.yaml --output supergraph.graphql
    - yq -i '.supergraphSchema = load_str("supergraph.graphql")' "env/${CI_ENVIRONMENT_NAME}/apollo-router/values.yaml"
    - git add "env/${CI_ENVIRONMENT_NAME}/apollo-router/values.yaml"
    - git commit -m "chore: recompose supergraph for ${CI_ENVIRONMENT_NAME}" || echo "no schema change"
    - git push origin HEAD:${CI_COMMIT_REF_NAME}
  rules:
    - if: '$CI_PIPELINE_SOURCE == "push" && ($CI_COMMIT_REF_NAME =~ /^us\// || $CI_COMMIT_REF_NAME =~ /^release\//)'
      variables:
        CI_ENVIRONMENT_NAME: sit
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes:
        - env/uat/**/*
      variables:
        CI_ENVIRONMENT_NAME: uat
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes:
        - env/production/**/*
      variables:
        CI_ENVIRONMENT_NAME: production

notify-n8n:
  stage: notify-n8n
  image: curlimages/curl:latest
  script:
    - |
      curl -X POST "$N8N_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"pipeline_id\": \"$CI_PIPELINE_ID\",
             \"status\": \"$CI_JOB_STATUS\",
             \"project\": \"$CI_PROJECT_NAME\",
             \"ref\": \"$CI_COMMIT_REF_NAME\"}"
  when: always
  needs:
    - secrets-scan
    - lint
    - test
    - sonarqube
    - dependency-scan
    - build
    - container-scan
```

### ArgoCD Application

```yaml
# services/{project}/argocd/{env}-{service}.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {project}-{service}-{env}
  namespace: argocd
spec:
  project: {project}
  source:
    repoURL: {gitlab-url}/{project}/services.git
    targetRevision: HEAD
    path: helm/{service}
    helm:
      # values live outside the chart — env/{environment-name}/{application-name}/values.yaml
      valueFiles:
        - ../../env/{env}/{service}/values.yaml
  destination:
    server: https://kubernetes.default.svc
    # {service-type} = backend|frontend, resolved via nx project root — see
    # "Namespace convention" above. Never a bare {env}, phase clusters are
    # multi-tenant.
    namespace: {env}-{project}-{service-type}-{service}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Apollo Router Provisioning (one instance per project, per env)

Runs once at `/kickoff` (new project) and once per new env the project
reaches — the router chart is shared, centrally maintained infra
(`helm/apollo-router` in homelab_setup2, packaged as an OCI artifact and
pushed to Harbor's `library/charts` by `terraform/internal/apollo-router-chart.tf`
— **never copied into this project's own repo**, unlike every
`helm/{service}` chart above). Only two things live in the project repo:

1. **The values file** — create `env/{env}/apollo-router/values.yaml` once,
   `supergraphSchema` starts empty (`compose-supergraph` fills it in on the
   first pipeline run after this):
   ```yaml
   supergraphSchema: ""
   ```
2. **The ArgoCD Application** — a multi-source Application: one source is
   the OCI chart (no `path`, references Harbor directly), the other is this
   project's own repo for the values file only (`ref: values`, combined via
   `$values` in `helm.valueFiles` — this is the standard ArgoCD pattern for
   "chart from repo A, values from repo B", not a workaround):
   ```yaml
   # services/{project}/argocd/{env}-apollo-router.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: {project}-apollo-router-{env}
     namespace: argocd
   spec:
     project: {project}
     sources:
       # ponytail: host.docker.internal:$REGISTRY_MIRROR_PORT, not
       # harbor.harbor.svc.cluster.local — sit/uat/production sit on separate
       # docker networks from internal (where Harbor actually runs) and can't
       # resolve its in-cluster DNS name; this is the SAME NodePort bridge
       # every image pull from those clusters already uses (see AGENT.md's
       # "Harbor" section), just addressed by ArgoCD's own OCI client instead
       # of containerd this time.
       - repoURL: oci://host.docker.internal:30500/library/charts
         chart: apollo-router
         targetRevision: "0.1.0"
         helm:
           valueFiles:
             - $values/env/{env}/apollo-router/values.yaml
       - repoURL: {gitlab-url}/{project}/services.git
         targetRevision: HEAD
         ref: values
     destination:
       server: https://kubernetes.default.svc
       # service-type is always "infra" here — see "Namespace convention"
       namespace: {env}-{project}-infra-apollo-router
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```
   `30500` is the default `REGISTRY_MIRROR_PORT` — confirm against this
   homelab's actual `.env` value rather than hardcoding blindly if it's ever
   been overridden.

Frontend's `VITE_GRAPHQL_URL`/equivalent env var (per env) points at this
router's in-cluster Service: `http://apollo-router.{env}-{project}-infra-apollo-router.svc.cluster.local:4000/graphql`
for SSR/build-time use, and the router's own Ingress (scaffold one, same
`.local`+tailnet dual-ingress pattern this homelab's own apps use) for
browser traffic.

### ArgoCD Image Updater annotation (SIT only)

```yaml
# In SIT ArgoCD app annotations:
annotations:
  argocd-image-updater.argoproj.io/image-list: >
    {service}={registry}/{project}/{service}
  argocd-image-updater.argoproj.io/{service}.update-strategy: latest
  argocd-image-updater.argoproj.io/{service}.allow-tags: >
    regexp:^v\d+\.\d+\.\d+-rc\d+$
```

Image Updater only on SIT — all other envs use explicit ArgoCD sync.

---

## Cluster Lifecycle

### Wake cluster

Loop over every project/service namespace on this env (`{env}-*` — see
"Namespace convention" above, never a single bare `{env}` namespace, this
cluster is multi-tenant):

```bash
for ns in $(kubectl get ns -o name | grep "^namespace/${env}-" | cut -d/ -f2); do
  kubectl scale deployment --all --replicas=1 -n "$ns"
  kubectl rollout status deployment --all -n "$ns"
done
echo "Cluster {env} is healthy"
```

### Sleep cluster

```bash
# Scale down every project/service workload namespace, same loop as above —
# never touch argocd/registry/monitoring/ingress namespaces (not matched by
# the {env}-* project-namespace prefix anyway, those are fixed cluster infra)
for ns in $(kubectl get ns -o name | grep "^namespace/${env}-" | cut -d/ -f2); do
  kubectl scale deployment --all --replicas=0 -n "$ns"
done
echo "Cluster {env} sleeping"
```

Cluster lifecycle rules — only 4 clusters exist (sit/uat/production/internal),
no separate QA or staging cluster:
- SIT: always on during sprint (also where QA runs story-level acceptance
  tests — no separate QA cluster), sleep after sprint complete
- UAT: wake on `/uat`, stays up through `/release_staging`'s promotion
  retag + staging-equivalent checks (k6 perf, security confirmation scan —
  no separate staging cluster, they run against UAT), sleep after release
  confirmed
- Production: always on
- Internal: always on (GitLab, n8n, ArgoCD, monitoring)

---

## Promotion Pipeline

Runs on `promote/v{X}.{Y}.{Z}` branch. **Retags the exact image already
tested through SIT + UAT — never rebuilds.** A rebuild from the same commit
is not provably the same bits (base image drift, build timestamps); QA/PO
signed off on a specific image, not a specific commit, so that's the image
that ships. There is no separate staging cluster — the full-version image
redeploys to the same UAT cluster for the staging-equivalent checks (k6
perf, security confirmation scan) that run before production.

```yaml
# .gitlab-ci.yml addition for promote branch only
promote-and-retag:
  stage: build
  image: docker:24-dind
  <<: *dind-service
  rules:
    - if: $CI_COMMIT_REF_NAME =~ /^promote\//
  script:
    - .ci/promote.sh
```

```bash
#!/usr/bin/env bash
# .ci/promote.sh
set -euo pipefail
# docker:24-dind is Alpine-based — jq/yq/bun (for nx) aren't preinstalled, apk is
apk add --no-cache jq yq bun
bun install --frozen-lockfile
# Harbor, not GitLab's own bundled registry — no $CI_REGISTRY_* auto-vars
# apply here (see AGENT.md's "Harbor" section, and build stage above).
docker login -u "$HARBOR_USER" -p "$HARBOR_PASSWORD" harbor.harbor.svc.cluster.local:80

# 1. The UAT-tested tag for each service is whatever's currently written in
#    env/uat/{service}/values.yaml (put there by /uat's pre-deploy step,
#    confirmed by QA/Security/PO sign-off since) — that IS the artifact,
#    read it back rather than re-deriving from package.json/git diff.
for f in env/uat/*/values.yaml; do
  SERVICE=$(basename "$(dirname "$f")")
  RC_TAG=$(yq '.image.tag' "$f")          # e.g. v1.2.0-rc3
  FULL_TAG="${RC_TAG%-rc*}"                # v1.2.0
  IMAGE="harbor.harbor.svc.cluster.local:80/library/${CI_PROJECT_PATH}/${SERVICE}"
  # SERVICE is the nx project name (env/{env}/{service} dir names match
  # project names, not the apps/backend|frontend/ nesting) — resolve its
  # actual app root to find the right package.json, same rule as build above.
  ROOT=$(bunx nx show project "$SERVICE" --json | jq -r .root)

  # 2. Retag — pull once, tag, push. No docker build anywhere in this script.
  docker pull "$IMAGE:$RC_TAG"
  docker tag  "$IMAGE:$RC_TAG" "$IMAGE:$FULL_TAG"
  docker push "$IMAGE:$FULL_TAG"

  # 3. Bump package.json to the full version too — changelog/version
  #    consistency only, this does NOT trigger a rebuild (promote/* branch
  #    isn't matched by the main `build` job's rules).
  jq ".version = \"${FULL_TAG#v}\"" "$ROOT/package.json" > tmp && mv tmp "$ROOT/package.json"

  # 4. Overwrite env/uat/{service}/values.yaml's tag with the full version —
  #    no separate staging cluster, the full-version image redeploys to the
  #    SAME UAT cluster for the staging-equivalent checks below. ArgoCD's
  #    automated sync on the UAT Application picks it up from here.
  yq -i ".image.tag = \"$FULL_TAG\"" "$f"
  git add "$ROOT/package.json" "$f"
done

git commit -m "chore: promote v{X}.{Y}.{Z} — retag rc images to full version, redeploy to UAT for staging checks"
git push origin "promote/v{X}.{Y}.{Z}"

# Wait for ArgoCD to actually roll the retagged image out before telling n8n
# staging is ready — otherwise F-15's k6/ZAP run against the stale rc image.
for f in env/uat/*/values.yaml; do
  SERVICE=$(basename "$(dirname "$f")")
  kubectl --context "$UAT_CLUSTER_CONTEXT" rollout status "deployment/$SERVICE" -n hr-portal --timeout=120s
done

# Nothing else in this pipeline calls webhook/staging-deployed — F-15 is
# unreachable without this. $N8N_STAGING_WEBHOOK is a GitLab CI/CD variable
# on THIS project (like $N8N_WEBHOOK_URL above), pointing at
# <n8n-base>/webhook/staging-deployed — set it at kickoff alongside the
# other CI variables, it doesn't exist by default.
curl -X POST "$N8N_STAGING_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "{\"version\": \"v{X}.{Y}.{Z}\"}"
```

---

## Behaviour Rules

- Gate A signal must only fire when ALL infra checks pass — never partial
- ArgoCD Image Updater is SIT only — never configure on UAT, staging, or production
- Promotion (rc → full version, staging, production) is always a retag of the UAT-tested image — never a rebuild. Source the tag to retag from `env/uat/{service}/values.yaml`, never from git diff/package.json
- Never scale down infra namespace (GitLab, n8n, ArgoCD, monitoring, ingress)
- CI pipeline `notify-n8n` job must have `needs:` listing all other jobs — pipeline contract enforced
- The promote-and-retag job must notify `$N8N_STAGING_WEBHOOK` after rollout, not just push — F-15/`webhook/staging-deployed` has no other trigger in the whole pipeline, skip this and the staging phase silently never runs
- All secrets via Kubernetes secrets or GitLab CI variables — never in config files
- Every helm chart's values live at `env/{environment-name}/{application-name}/values.yaml`, never inline in the ArgoCD Application and never as environment-specific data inside `helm/{service}/values.yaml` — every ArgoCD Application for the chart must set `source.helm.valueFiles` to it
