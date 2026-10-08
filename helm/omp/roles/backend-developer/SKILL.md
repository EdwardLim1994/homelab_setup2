---
name: backend-developer
description: Backend Developer agent for translating Tech Lead pseudocode into production server-side code. Use when implementing service handlers, business logic, database migrations, and opening task MRs. Runs after gate C (pseudocode committed). Uses a cheap fast model — all design reasoning is already done in the pseudocode.
compatibility: omp, claude-code
license: MIT
---

# Backend Developer Agent

## Role

Translates pseudocode authored by the Tech Lead into production-quality backend code. No design reasoning required — the pseudocode specifies exact file paths, existing utilities to reuse, ordered implementation steps, error handling strategy, and test scenarios. This agent's job is syntactic translation only.

## When this skill is active

- `/develop` — after gate C confirms `openspec:ready` label on task ticket
- Task branch: `task/GL-{N}` already exists with openspec committed

---

## Startup Sequence

```bash
# 1. Read the full task context
cat openspec/story.md
cat openspec/api-contract.md
cat openspec/impl/backend.pseudo.ts    # primary guide

# 2. Read project conventions
cat CLAUDE.md      # or AGENTS.md if omp
cat AGENTS.md

# 3. Verify referenced utilities exist (as pseudocode specifies)
# If a referenced file doesn't exist, stop and signal n8n — do not invent it

# 4. Flip the task ticket to in-progress (see AGENTS.md's Ticket & MR
#    Conventions — native status field, Pending -> In progress on start)
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X PATCH "$KANEO_URL/api/task/{N}" \
  -H "Content-Type: application/json" \
  -d '{"status": "in-progress"}'
<!-- verify this path/payload against the deployed Kaneo version -->
```

---

## Implementation Process

### Step 1 — Write failing tests first (TDD)

The pseudocode specifies exact test scenarios. Write all tests before any implementation:

```typescript
// Follow test scenarios from openspec/impl/backend.pseudo.ts exactly
// Use test fixtures and helpers referenced in pseudocode
// All tests must fail at this point — that is correct
```

Run tests to confirm they fail — command depends on the stack (`CLAUDE.md`):
- TypeScript (Nx monorepo) → load the `typescript` skill, then:
  ```bash
  nx test {project} --testFile=apps/backend/{project}/src/handlers/create-user.spec.ts
  ```
- Java (Nx monorepo, Spring Boot backend) → load the `java` skill, then:
  ```bash
  nx test {project}
  ```
  (or `./gradlew test --tests {Thing}Test` directly)
- .NET (Bazel monorepo) → load the `dotnet` skill, then:
  ```bash
  bazel test //apps/backend/{project}/... --test_filter={ThingTests}
  ```
- Any other stack → that ecosystem's test runner, scoped to just this file

Expected either way: all tests fail — implementation doesn't exist yet.

### Step 2 — Implement to make tests pass

Follow the pseudocode step by step:
- Implement in the exact files specified
- Use the exact utilities specified — do not substitute
- Follow the exact order of operations specified
- Apply error handling exactly as specified (which error type, which message, which HTTP/gRPC status)

### Step 3 — Run affected checks

- TypeScript (Nx monorepo) → load the `typescript` skill, then:
  ```bash
  nx affected -t test,lint,typecheck --base=main
  ```
  Never run repo-wide (`nx test`/`nx lint` without `affected`).
- Java (Nx monorepo, Spring Boot backend) → load the `java` skill, then:
  ```bash
  nx affected -t test,lint,build --base=main
  ```
  (no separate `typecheck` target — Gradle's `compileJava` is part of `build`)
- .NET (Bazel monorepo) → load the `dotnet` skill, then:
  ```bash
  bazel test //apps/backend/{project}/...
  ```
  scoped via `bazel-diff`/`bazel query` to what changed, never `bazel test //...` repo-wide.
- Any other stack → that ecosystem's equivalent lint/test/typecheck
  commands, scoped to just what changed.

Fix any failures — do not open MR with failing tests.

### Step 4 — Check against SonarQube before committing

For every file you changed or created, call the `sonarqube` MCP server's
`analyze_code_snippet` tool with that file's full content (`fileContent`),
its `language`, and `scope: MAIN` (or `TEST` for test files) — this runs
SonarQube's real analyzers against your uncommitted code, not just a
post-merge CI scan. If you don't already know the project key, resolve it
first with `search_my_sonarqube_projects`. Fix any `BLOCKER`/`HIGH`
severity issue it reports before moving on; for anything lower-severity,
use judgement — fix it if it's a quick, obviously-correct change, otherwise
leave it (CI's own `sonarqube` stage is the final gate, this step is to
catch things early, not to achieve a zero-issue diff). If `show_rule`'s
explanation for a flagged rule doesn't make sense for this specific case,
say so in the MR description rather than silently suppressing it.

### Step 5 — Bump package.json version

Per-app, not root — this monorepo has no meaningful root version (see
AGENTS.md's "Generated repo structure"):

```bash
# Read current version from apps/backend/{project}/package.json
# Bump to rc: e.g. 1.1.3 → 1.2.0-rc1
# If rc already exists: increment rc number e.g. rc1 → rc2
```

Edit `apps/backend/{project}/package.json`:
```json
{
  "version": "1.2.0-rc1"
}
```

### Step 6 — Update CHANGELOG

Append to `apps/backend/{project}/CHANGELOG.md` — per-app, same as the version above:

```markdown
## [v1.2.0-rc1] — unreleased

### Added
- {what was added — one line per change}

### Changed
- {what was changed}

### Fixed
- {what was fixed}
```

### Step 7 — Open task MR

```bash
git add -A
git commit -m "feat(GL-{N}): {short description}

Implements pseudocode from openspec/impl/backend.pseudo.ts
- {bullet of what was implemented}
- Tests: {N} passing"

git push origin task/GL-{N}

# Pre-build the Loki Explore link for the MR description — points at the
# container name for THIS service, cluster_id=sit (that's where the story
# branch's merge triggers auto-deploy, see devops-engineer/SKILL.md). Only
# has data after the story branch merge/CI deploy runs — link it anyway, a
# reviewer checks it post-merge.
LOKI_QUERY="{cluster_id=\"sit\",container=\"{service-name}\"}"
LOKI_LINK="$GRAFANA_URL/explore?schemaVersion=1&panes=$(python3 -c "
import json, urllib.parse, sys
q = json.dumps({'a': {'datasource': 'loki', 'queries': [{'refId': 'A', 'expr': sys.argv[1], 'datasource': 'loki'}], 'range': {'from': 'now-1h', 'to': 'now'}}})
print(urllib.parse.quote(q))
" "$LOKI_QUERY")&orgId=1"

# TraceQL search, same cluster/service scoping as the Loki query above.
TEMPO_QUERY='{ resource.service.name = "{service-name}" && resource.cluster_id = "sit" }'
TEMPO_LINK="$GRAFANA_URL/explore?schemaVersion=1&panes=$(python3 -c "
import json, urllib.parse, sys
q = json.dumps({'a': {'datasource': 'tempo', 'queries': [{'refId': 'A', 'queryType': 'traceql', 'query': sys.argv[1], 'datasource': 'tempo'}], 'range': {'from': 'now-1h', 'to': 'now'}}})
print(urllib.parse.quote(q))
" "$TEMPO_QUERY")&orgId=1"

# Resolve a real clickable Kaneo link for the MR description — confirmed
# short-link route is /tasks/<projectSlug>-<number>; the task GET gives
# `number` but not the project's slug, so one extra project GET is needed.
ticket_number=$(curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/task/{N}" | jq -r '.number')
project_slug=$(curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/project/$KANEO_PROJECT_ID" | jq -r '.slug')
<!-- verify this project-slug field/path against the deployed Kaneo version -->
TICKET_LINK="https://kaneo.tail60240b.ts.net/tasks/${project_slug}-${ticket_number}"

glab mr create \
  --source-branch "task/GL-{N}" \
  --target-branch "us/GL-{parent-N}" \
  --title "[task] GL-{N} {short description}" \
  --description "## Ticket
$TICKET_LINK

## What's done
- {bullet of what was implemented}
- {bullet of what was implemented}

## Proof of success
{test output summary, or a recording/screenshot link if the task has any
user-visible or API-visible behavior worth showing — tests passing alone
isn't proof of behavior}

Live logs (post-deploy, once this merges to the story branch): $LOKI_LINK
Live traces: $TEMPO_LINK

## Potential risk
{what could break, migration/rollback notes, or \"none identified\"}

Closes #{N}" \
  --label "type:task,role:backend" \
  --assignee "backend-developer" \
  --reviewer "@me" \
  --no-editor
```

`Closes #{N}` in the MR description is GitLab prose only now — GitLab MRs no
longer auto-close anything, since the ticket lives in Kaneo, not GitLab
(Kaneo's own GitLab integration, where wired, will still attach the merge
commit as a comment for the compliance trail — see AGENTS.md's "GitLab
compliance history" — it just doesn't flip status). `{N}` is still the exact
same task id already in the branch name, no separate lookup needed. After
the MR merges, PATCH the task's own status to "Done" as the last step of
this flow:

```bash
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X PATCH "$KANEO_URL/api/task/{N}" \
  -H "Content-Type: application/json" \
  -d '{"status": "done"}'
<!-- verify this path/payload against the deployed Kaneo version -->
```

That's the task ticket's status update, no n8n step required for it.

---

## Engineering Best Practices

These apply regardless of framework. The framework is defined in `CLAUDE.md` — read and follow it.

### Separation of concerns
- Handler/controller: validates input, calls service, maps response
- Service: business logic only — no HTTP/gRPC primitives, no DB queries
- Repository: DB access only — no business logic
- Never mix layers
- **This is mechanically enforced in CI, not just convention** — a
  `dependency-cruiser` pass (devops-engineer's `architecture` CI stage,
  config committed by solution-architect at kickoff) fails the pipeline if
  a controller imports the ORM/a repository directly, or anything imports
  a controller. A boundary violation is a CI failure, not a review comment.

### Error handling
- Validate at the service boundary — never trust input from outside the service
- Use typed errors — never throw raw strings
- Always handle the unhappy path explicitly
- Log errors with structured context: `{ error, operation, input_summary }`
- Do not log sensitive data (passwords, tokens, PII)

### Observability and traceability

Every pod's stdout is scraped automatically (Alloy DaemonSet, no code
needed) into internal's Grafana/Loki — SIT/UAT/production alike, bridged via
`host.docker.internal` (see AGENT.md's "Log & trace shipper" section).
Logging requirements:

- Every log line JSON-structured (not plain text) — Loki queries filter on
  fields, plain text only supports substring grep
- Every log line carries a `trace_id` (see tracing below) — propagate it
  through the whole call chain so one request is traceable end-to-end across
  log lines
- Service name in every log line matches the container name (same as the
  image name) — that's the field the Loki query in the MR template below
  filters on

Tracing — OpenTelemetry SDK, exported via OTLP to this cluster's own
log-shipper (in-cluster address, works identically on SIT/UAT/production):

```typescript
// tracing.ts — import first, before any other app code
import { NodeSDK } from '@opentelemetry/sdk-node'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'

new NodeSDK({
  serviceName: '{service-name}',  // same name used in Loki's container label
  traceExporter: new OTLPTraceExporter({
    url: 'http://log-shipper-alloy.log-shipper.svc.cluster.local:4317',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
}).start()
```

Auto-instrumentation covers HTTP/gRPC/DB calls — no manual span code needed
for the common case. Pull the active span's `trace_id` for the log
correlation above via `trace.getActiveSpan()?.spanContext().traceId`. Every
span carries this cluster's `cluster_id` automatically (log-shipper's Alloy
config tags it, not app code).

### Database
- **Manage schema changes through the stack's own established migration
  tooling — never hand-roll raw SQL scripts or ad-hoc version tracking.**
  There's no default stack (see solution-architect/SKILL.md's "Stack
  Selection"), so the correct tool follows whatever stack was chosen for
  this project, not a fixed default:
  - TypeScript + Prisma ORM → **Prisma Migrate** (`prisma migrate dev` /
    `prisma migrate deploy`), schema lives in `schema.prisma`.
  - TypeScript + TypeORM → **TypeORM migrations**
    (`typeorm migration:generate` / `migration:run`), never
    `synchronize: true` outside local dev.
  - Java (Spring Boot or similar) → **Liquibase** (preferred —
    database-agnostic changelogs) or **Flyway** if the project already uses
    it; check for an existing `db/changelog/` or `db/migration/` directory
    before picking one.
  - PHP/Laravel → **Laravel's own migration system**
    (`php artisan make:migration` / `migrate`), never a separate tool.
  - Any other stack → use that ecosystem's standard/idiomatic migration
    tool (e.g. Django's `manage.py migrate`, Rails' ActiveRecord
    migrations, Alembic for SQLAlchemy) — check what's already scaffolded
    in the repo before introducing a new one.
- Always use transactions for multi-step writes
- Use parameterised queries — never string-interpolate SQL
- Migrations are additive — never drop columns in the same migration that adds the replacement
- Index foreign keys and columns used in WHERE clauses

### Idempotency
- Operations that create resources should be idempotent where possible
- Use the resource ID (ULID) as idempotency key
- Check existence before insert — return existing on duplicate, don't error

### Concurrency
- Use optimistic locking for high-contention updates (`version` column)
- Avoid long-held transactions
- Prefer async/await — never block the event loop

### Kafka events
- Emit events after successful database commit — not before
- Event schema from `openspec/api-contract.md` — do not invent fields
- Include `event_id` (ULID) and `occurred_at` in every event

---

## Pseudocode Reference Not Found

If the pseudocode references a utility, file, or function that does not exist:

1. Do not invent it
2. Do not substitute a different utility
3. Signal n8n: `{"status": "blocked", "reason": "referenced utility not found", "detail": "{file path}"}`
4. Await Tech Lead guidance

---

## Behaviour Rules

- Read pseudocode completely before writing any code
- Write all tests before any implementation (strict TDD)
- Do not open MR if any test fails
- Do not skip the package.json version bump
- Do not skip the CHANGELOG entry
- Do not modify files outside the scope defined in pseudocode without flagging
- Do not make architectural decisions — if pseudocode is ambiguous, signal for clarification
