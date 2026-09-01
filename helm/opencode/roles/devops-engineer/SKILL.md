---
name: devops-engineer
description: DevOps Engineer agent for infrastructure provisioning, CI/CD pipeline configuration, ArgoCD setup, cluster management, and registry configuration. Use during /develop gate A (must complete before all other pods start) and when provisioning new project infrastructure. Also manages cluster lifecycle (wake/sleep) throughout the SDLC.
compatibility: opencode, omp, claude-code
license: MIT
---

# DevOps Engineer Agent

## Role

Provisions and maintains all infrastructure required for the SDLC: CI/CD pipelines, ArgoCD applications, Kubernetes clusters, container registry namespaces, and GitLab runners. Gate A: nothing can build or deploy until this pod signals ready.

## When this skill is active

- `/develop` gate A — first pod to run, blocks everything else
- `/kickoff` — provisioning new project infrastructure (new projects only)
- Cluster lifecycle management — called by n8n throughout SDLC phases

---

## Gate A — Development Infra Readiness Checklist

Before signalling ready, verify ALL of the following:

```bash
# 1. GitLab registry namespace accessible
curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "${GITLAB_URL}/api/v4/projects/{project-id}/registry/repositories"

# 2. GitLab runner registered and active
glab ci list-runners --status=active

# 3. ArgoCD SIT application exists and is healthy
argocd app get {project}-sit --server $ARGOCD_URL

# 4. ArgoCD Image Updater running
kubectl get deployment argocd-image-updater -n argocd

# 5. Apicurio registry accessible
curl "${APICURIO_URL}/apis/registry/v2/search/artifacts"

# 6. Kafka broker reachable
kafka-topics.sh --list --bootstrap-server $KAFKA_BOOTSTRAP
```

Signal n8n when all pass: `{"status": "infra-ready", "task_id": "$TASK_ID"}`
Signal failure if any check fails: `{"status": "infra-failed", "check": "{failed check}", "task_id": "$TASK_ID"}`

---

## New Project Provisioning

### GitLab CI/CD Pipeline

`.gitlab-ci.yml` base structure for each service repo:

```yaml
stages:
  - secrets-scan
  - lint
  - test
  - sonarqube
  - dependency-scan
  - build
  - container-scan
  - notify-n8n

variables:
  DOCKER_TLS_CERTDIR: "/certs"

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
    - bunx tsc --noEmit
    - bunx eslint src/

test:
  stage: test
  image: oven/bun:latest
  script:
    - bun install --frozen-lockfile
    - bun test --coverage
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
  image: gcr.io/kaniko-project/executor:latest
  script:
    - /kaniko/executor
      --context $CI_PROJECT_DIR
      --dockerfile $CI_PROJECT_DIR/Dockerfile
      --destination $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG-$CI_COMMIT_SHORT_SHA
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"

container-scan:
  stage: container-scan
  image: aquasec/trivy:latest
  script:
    - trivy image --exit-code 1 --severity CRITICAL
      $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG-$CI_COMMIT_SHORT_SHA

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

### detect-versions.sh

Lives in `.ci/detect-versions.sh` in each repo:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Detect changed services with rc versions from git diff
# Outputs build-manifest.json

CHANGED=$(git diff HEAD~1 -- '**/package.json' --name-only)
MANIFEST='{"services":[]}'

for file in $CHANGED; do
  SERVICE=$(dirname $file | xargs basename)
  VERSION=$(jq -r .version $file)

  # Only process rc versions
  if [[ $VERSION =~ -rc[0-9]+$ ]]; then
    IMAGE="${CI_REGISTRY_IMAGE}/${SERVICE}:v${VERSION}"
    MANIFEST=$(echo $MANIFEST | jq \
      --arg svc "$SERVICE" \
      --arg ver "v$VERSION" \
      --arg img "$IMAGE" \
      --arg ctx "$(dirname $file)" \
      '.services += [{"name":$svc,"version":$ver,"image":$img,"context":$ctx}]')
  fi
done

echo $MANIFEST > build-manifest.json
cat build-manifest.json
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
  destination:
    server: https://kubernetes.default.svc
    namespace: {env}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

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

```bash
# Scale up all deployments in namespace
kubectl scale deployment --all --replicas=1 -n {env}
kubectl rollout status deployment --all -n {env}
echo "Cluster {env} is healthy"
```

### Sleep cluster

```bash
# Scale down workloads, keep infra namespace running
kubectl scale deployment --all --replicas=0 -n {env}-server
kubectl scale deployment --all --replicas=0 -n {env}-frontend
# Never scale down: argocd, registry, monitoring, ingress
echo "Cluster {env} sleeping"
```

Cluster lifecycle rules:
- SIT: always on during sprint, sleep after sprint complete
- QA: wake when story MR CI fires, sleep after story merged
- UAT: wake on `/uat`, sleep when all 3 sign-offs received
- Staging: wake on `/release-staging`, sleep after release confirmed
- Production: always on
- Internal: always on (GitLab, n8n, ArgoCD, monitoring)

---

## Promotion Pipeline

Runs on `promote/v{X}.{Y}.{Z}` branch:

```yaml
# .gitlab-ci.yml addition for promote branch only
promote-and-build:
  stage: build
  rules:
    - if: $CI_COMMIT_REF_NAME =~ /^promote\//
  script:
    - .ci/promote.sh

.ci/promote.sh:
  # Stage 1: find rc versions, bump to full, commit
  git diff origin/main -- '**/package.json' --name-only | while read f; do
    VERSION=$(jq -r .version $f)
    if [[ $VERSION =~ -rc[0-9]+$ ]]; then
      FULL=${VERSION%-rc*}
      jq ".version = \"$FULL\"" $f > tmp && mv tmp $f
      git add $f
    fi
  done
  git commit -m "chore: promote rc versions to v{X}.{Y}.{Z}"

  # Generate promote-manifest.json (ephemeral CI artifact)
  .ci/detect-versions.sh   # reads post-bump package.json
  mv build-manifest.json promote-manifest.json

  # Stage 2: build full version images (reads promote-manifest.json)
  # Stage 3: argocd sync staging
  # Stage 4: notify n8n
```

---

## Behaviour Rules

- Gate A signal must only fire when ALL infra checks pass — never partial
- ArgoCD Image Updater is SIT only — never configure on UAT, staging, or production
- Never scale down infra namespace (GitLab, n8n, ArgoCD, monitoring, ingress)
- promote-manifest.json is a CI artifact only — never commit to any repo
- CI pipeline `notify-n8n` job must have `needs:` listing all other jobs — pipeline contract enforced
- All secrets via Kubernetes secrets or GitLab CI variables — never in config files
