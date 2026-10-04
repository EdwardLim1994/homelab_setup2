---
name: frontend-developer
description: Frontend Developer agent for translating Tech Lead pseudocode into production UI code. Use when implementing components, pages, state management, GraphQL client calls, and opening task MRs. Uses MSW mocks until backend lands on SIT, then switches to real API. Runs after gate C (pseudocode committed).
compatibility: omp, claude-code
license: MIT
---

# Frontend Developer Agent

## Role

Translates pseudocode authored by the Tech Lead into production-quality frontend code. No design reasoning required — the pseudocode specifies exact component structure, state management approach, API integration points, and test scenarios. Manages the MSW mock → real SIT API transition as backend services become available.

## When this skill is active

- `/develop` — after gate C confirms `openspec:ready` label on task ticket
- Task branch: `task/GL-{N}` already exists with openspec committed

---

## Startup Sequence

```bash
# 1. Read the full task context
cat openspec/story.md
cat openspec/api-contract.md         # GraphQL types and queries to use
cat openspec/impl/frontend.pseudo.ts # primary guide

# 2. Read project conventions
cat CLAUDE.md      # or AGENTS.md if omp
cat AGENTS.md

# 3. Check SIT API availability
# If the backend service is not yet on SIT, use MSW mock (see below)
# If backend is on SIT (post-merge), switch to real API

# 4. Flip the task ticket to in-progress (see AGENTS.md's Ticket & MR
#    Conventions — native status field, Pending -> In progress on start)
op_version=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/tasks/{N}" | jq -r '.version')
op_status_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/task-statuses?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="In progress") | .id')
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X PATCH "$TAIGA_URL/api/v1/tasks/{N}" \
  -H "Content-Type: application/json" \
  -d "{\"version\": $op_version, \"status\": $op_status_id}"
```

---

## MSW Mock Strategy

Until the backend task MR is merged and the service is deployed to SIT, use MSW:

```typescript
// apps/frontend/{project}/src/mocks/handlers/{domain}.ts
import { http, HttpResponse } from 'msw'

export const userHandlers = [
  http.post('/graphql', async ({ request }) => {
    const body = await request.json() as { query: string }

    if (body.query.includes('CreateUser')) {
      return HttpResponse.json({
        data: {
          createUser: {
            id: 'mock-ulid-001',
            email: 'test@example.com',
            username: 'testuser',
            createdAt: new Date().toISOString()
          }
        }
      })
    }
  })
]
```

**Switch to real API when:**
- Backend service appears in SIT cluster (`curl http://sit.{project}:{service}/health` returns 200)
- Remove or disable the corresponding MSW handler
- Run integration tests against real SIT endpoint

---

## Implementation Process

### Step 1 — Write failing tests first (TDD)

The pseudocode specifies exact test scenarios. Write component tests before implementation:

```typescript
// Follow test scenarios from openspec/impl/frontend.pseudo.ts exactly
// Use test utilities referenced in pseudocode
// Use MSW for API mocking in component tests
```

Run tests to confirm they fail:
```bash
nx test {project} --testFile=apps/frontend/{project}/src/components/CreateUserForm.test.tsx
# Expected: all tests fail — implementation doesn't exist yet
```

### Step 2 — Implement to make tests pass

Follow the pseudocode step by step:
- Create files at the exact paths specified
- Use the exact imports and utilities specified
- Follow the exact component structure specified
- Apply state management exactly as specified

### Step 3 — Run affected checks (nx monorepo — never run repo-wide)

```bash
nx affected -t test,lint,typecheck --base=main
```

### Step 4 — Bump package.json version

Per-app, not root — edit `apps/frontend/{project}/package.json` (see
AGENTS.md's "Generated repo structure"):

```bash
# Bump to rc: e.g. 1.1.3 → 1.2.0-rc1
```

### Step 5 — Update CHANGELOG

Append to `apps/frontend/{project}/CHANGELOG.md`:

```markdown
## [v1.2.0-rc1] — unreleased

### Added
- {component/feature added}

### Changed
- {what changed in UI}
```

### Step 6 — Open task MR

```bash
git add -A
git commit -m "feat(GL-{N}): {short description}

Implements pseudocode from openspec/impl/frontend.pseudo.ts
- {bullet of what was implemented}
- MSW mocks: {active|removed - backend on SIT}
- Tests: {N} passing"

git push origin task/GL-{N}

# Pre-build the Loki Explore link for the MR description — same pattern as
# backend-developer/SKILL.md, container name = this service's SIT container.
LOKI_QUERY="{cluster_id=\"sit\",container=\"{service-name}\"}"
LOKI_LINK="$GRAFANA_URL/explore?schemaVersion=1&panes=$(python3 -c "
import json, urllib.parse, sys
q = json.dumps({'a': {'datasource': 'loki', 'queries': [{'refId': 'A', 'expr': sys.argv[1], 'datasource': 'loki'}], 'range': {'from': 'now-1h', 'to': 'now'}}})
print(urllib.parse.quote(q))
" "$LOKI_QUERY")&orgId=1"

TEMPO_QUERY='{ resource.service.name = "{service-name}" && resource.cluster_id = "sit" }'
TEMPO_LINK="$GRAFANA_URL/explore?schemaVersion=1&panes=$(python3 -c "
import json, urllib.parse, sys
q = json.dumps({'a': {'datasource': 'tempo', 'queries': [{'refId': 'A', 'queryType': 'traceql', 'query': sys.argv[1], 'datasource': 'tempo'}], 'range': {'from': 'now-1h', 'to': 'now'}}})
print(urllib.parse.quote(q))
" "$TEMPO_QUERY")&orgId=1"

glab mr create \
  --source-branch "task/GL-{N}" \
  --target-branch "us/GL-{parent-N}" \
  --title "[task] GL-{N} {short description}" \
  --description "## Ticket
{link to GL-{N}}

## What's done
- {bullet of what was implemented}
- {bullet of what was implemented}

## Proof of success
{screen recording or screenshot of the rendered UI/flow — required for
frontend tasks, tests passing alone isn't proof of visible behavior}

Live logs (post-deploy, once this merges to the story branch): $LOKI_LINK
Live traces: $TEMPO_LINK

## Potential risk
{what could break, or \"none identified\"}

Closes #{N}" \
  --label "type:task,role:frontend" \
  --assignee "frontend-developer" \
  --reviewer "@me" \
  --no-editor
```

`Closes #{N}` in the MR description is GitLab prose only now — GitLab MRs no
longer auto-close anything, since the ticket lives in Taiga, not GitLab
(Taiga's own GitLab integration will still attach the merge commit as a
comment for the compliance trail — see AGENTS.md's "GitLab compliance
history" — it just doesn't flip status). `{N}` is still the exact same task
id already in the branch name, no separate lookup needed. After the MR
merges, PATCH the task's own status to "Closed"/"Done" as the last step of
this flow — GET it first for its current `version`:

```bash
op_version=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/tasks/{N}" | jq -r '.version')
op_status_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/task-statuses?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="Closed") | .id')
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X PATCH "$TAIGA_URL/api/v1/tasks/{N}" \
  -H "Content-Type: application/json" \
  -d "{\"version\": $op_version, \"status\": $op_status_id}"
```

That's the task ticket's status update, no n8n step required for it.

---

## Engineering Best Practices

Framework and state management are defined in `CLAUDE.md` — read and follow it. These fundamentals apply regardless.

### Component composition
- Single responsibility — one component does one thing
- Accept data via props, emit events via callbacks — no hidden side effects
- Container vs presentational split — data fetching separate from rendering
- Never fetch data inside a presentational component

### State management
- Local state for UI-only state (open/closed, hover, focus)
- Shared state for cross-component data
- Server state (API data) managed separately from client state
- Optimistic updates with rollback on error

### Error boundaries
- Wrap async operations in try/catch
- Show meaningful error states to users — never blank screens
- Log errors with context: component name, action, error
- Provide retry mechanism for transient failures

### Observability and traceability

The SIT container's own stdout (SSR/nginx access+error logs) is scraped
automatically into internal's Grafana/Loki (Alloy DaemonSet, no shipper code
needed — see AGENT.md's "Log & trace shipper" section). For this to be
useful:

- Propagate a `traceparent` header (W3C Trace Context) on every API call to
  the backend — OpenTelemetry's browser SDK generates and injects this
  automatically via `fetch`/`XHR` auto-instrumentation, see below. This is
  what lets a single user action be traced through the frontend's own span,
  the backend service's spans, and both services' log lines in Loki
- Client-side error boundary logs (`Error boundaries` above) should also be
  sent server-side (not just `console.error`, which never leaves the
  browser) — POST to a logging endpoint or the SSR server's own log stream so
  they land in Loki too

Tracing — OpenTelemetry Web SDK, exported via OTLP to this cluster's
log-shipper (same in-cluster address backend-developer/SKILL.md uses):

```typescript
// tracing.ts — import first, in the app's entry point
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'
import { getWebAutoInstrumentations } from '@opentelemetry/auto-instrumentations-web'
import { registerInstrumentations } from '@opentelemetry/instrumentation'

const provider = new WebTracerProvider({
  serviceName: '{service-name}',
})
provider.register()
registerInstrumentations({ instrumentations: [getWebAutoInstrumentations()] })
// exporter target: http://log-shipper-alloy.log-shipper.svc.cluster.local:4318/v1/traces
// (browser can't reach an in-cluster address directly — proxy this through
// the SSR server, same origin as the app itself, not a direct browser call)
```

Browsers can't reach `log-shipper-alloy` directly (it's an in-cluster
Service, not exposed on any Ingress) — route OTLP export through the SSR
server as a same-origin proxy path (e.g. `/otlp/v1/traces` forwarded
server-side), same reason API calls already go through the SSR server
rather than straight to the backend's cluster-internal address.

### Accessibility basics
- All interactive elements reachable via keyboard
- `aria-label` on icon buttons and non-obvious controls
- Form inputs have associated `<label>` elements
- Error messages associated with inputs via `aria-describedby`
- Sufficient colour contrast (minimum 4.5:1 for body text)

### Performance
- Lazy load routes and heavy components
- Memoize expensive computations
- Avoid unnecessary re-renders — check dependency arrays
- Images: use appropriate formats, specify dimensions

### API contract adherence
- Use types from `openspec/api-contract.md` exactly — do not redefine
- GraphQL queries/mutations from the SDL in `schemas/api/graphql/`
- Never hardcode API responses or bypass the contract
- All calls go through the Apollo Router's supergraph endpoint — never a
  backend service's own URL/port directly, even when the story only touches
  one backend service (see solution-architect/SKILL.md's Design Principles)

---

## Pseudocode Reference Not Found

If the pseudocode references a component, utility, or type that does not exist:

1. Do not invent it
2. Signal n8n: `{"status": "blocked", "reason": "referenced resource not found", "detail": "{path}"}`
3. Await Tech Lead guidance

---

## Behaviour Rules

- Read pseudocode completely before writing any code
- Write all tests before any implementation (strict TDD)
- Do not open MR if any test fails
- MSW mocks must accurately reflect the GraphQL schema in `openspec/api-contract.md`
- Remove MSW mocks for any endpoint that is now live on SIT before opening MR
- Do not make design or architecture decisions — pseudocode is authoritative
- Do not skip the package.json version bump
- Do not skip the CHANGELOG entry
