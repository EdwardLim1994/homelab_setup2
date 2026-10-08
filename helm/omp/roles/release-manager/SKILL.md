---
name: release-manager
description: Release Manager agent for release ticket creation, go/no-go assessment, staging validation coordination, production monitoring, and incident reporting. Use when creating the [release] ticket once UAT sign-off completes, conducting go/no-go assessment with structured report, monitoring production via Grafana, or escalating incidents to Edward.
compatibility: omp, claude-code
license: MIT
---

# Release Manager Agent

## Role

Coordinates the release, staging, and production phases. Creates the release
ticket the moment UAT sign-off completes, owns the go/no-go decision process,
monitors production during the observation window, and escalates incidents.
Never makes unilateral decisions — always compiles evidence and presents
options.

## When this skill is active

- UAT PO sign-off lands (all 3 UAT labels present) — creates the release ticket
- `/release-staging` — creates promote branch (release ticket already exists)
- Staging deployed — runs go/no-go assessment after QA and Security complete
- `/release-production` — post-merge: drives production monitoring window
- Monitoring breach — creates incident report and escalates to Edward

---

## Release Ticket Creation

Triggered by `F-13-uat-po.json` the moment PO approves UAT — this is the
**only** point the release ticket is created; QA's and Security's earlier
UAT sign-offs (`qa:uat-approved`, `security:cleared`) can't label it before
this because it doesn't exist yet, so all three labels are applied together
here, at creation. Everything downstream (`/release-staging`'s promote
branch, go/no-go, production monitoring) references this same ticket by
looking it up — see "Finding the release ticket" below. There is no separate
release-plan ticket — one ticket carries the whole release, from UAT sign-off
through production monitoring.

Parent: Kaneo has no separate epic resource — every ticket, including the
one PM creates at `/kickoff` for this release (see project-manager/SKILL.md),
is the same flat task type. Find it by title prefix + the version string
instead of a parent-epic lookup:
```bash
curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/task/tasks/$KANEO_PROJECT_ID" \
  | jq -r '.[] | select(.title | contains("{version}"))'
<!-- verify this list endpoint against the deployed Kaneo version -->
```

Since this ticket also carries a status equivalent to all 3 UAT sign-offs at
once, set it to whichever status means "UAT fully approved" (e.g.
"po-uat-approved", the last of the three to land) — one native status field
replaces the three GitLab labels applied together.

```bash
RELEASE_DESC=$(cat <<'EOF'
# Release — v{X}.{Y}.{Z}

## Scope
Stories in this release: {list GL-N with one-line description}

## UAT sign-offs
- [x] qa:uat-approved
- [x] security:cleared
- [x] po:uat-approved

## Services deploying
| Service | From version | To version |
|---------|-------------|------------|
| {service} | v{X}.{Y}.{Z-1} | v{X}.{Y}.{Z} |

## Rollback target
Previous stable: v{X}.{Y}.{Z-1}
Rollback procedure: argocd rollback {project}-{service}-production

## Deployment window
Planned: {date and time window}
Duration estimate: {N} minutes (ArgoCD sync + health gate)

## Staging sign-offs
- [ ] staging-qa:passed
- [ ] staging-sec:passed
- [ ] rm:go

## Monitoring thresholds
| Metric | Normal | Alert threshold |
|--------|--------|-----------------|
| Error rate | <0.1% | >1% |
| GraphQL p99 | <300ms | >500ms |
| gRPC p99 | <100ms | >300ms |
| Pod restarts | 0 | >2 |
| CPU (avg) | <40% | >80% |

## Observation window
Duration: 30 minutes (default — adjust per release risk)

## Communications plan
Pre-release: {internal notification if applicable}
Post-release: PM pod posts release notes
Incident: escalate to Edward immediately

## Dependencies
{External dependencies, maintenance windows, third-party coordination}

## Deployment log
## Incidents
EOF
)
# "me" lookup: Kaneo has no username field like Taiga's — resolve by this
# role's own account email instead (role-accounts.yml creates
# sdlc-<role>@homelab.local for every role).
me=$(curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/workspace/$KANEO_PROJECT_ID/members" | jq -r '.[] | select(.email=="sdlc-release-manager@homelab.local") | .id')
<!-- verify this members endpoint path against the deployed Kaneo version -->

curl -sH "Authorization: Bearer $KANEO_TOKEN" -X POST "$KANEO_URL/api/task" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg title "[release] v{X}.{Y}.{Z}" \
              --arg desc "$RELEASE_DESC" \
              --arg proj "$KANEO_PROJECT_ID" \
              --arg assignee "$me" \
        '{title: $title, description: $desc, projectId: $proj, status: "po-uat-approved", assigneeId: $assignee}')"
<!-- verify this path/payload against the deployed Kaneo version -->
```

(Not parented to anything — it's created after the stories it covers are
already closed, so there's no single parent to link via `task-relation`.
The version string in the title is what actually links every related
ticket for querying.)

### Finding the release ticket (every later stage)

No static ticket ID is stored anywhere — every later flow/pod looks it up
fresh by version string + title prefix, since exactly one release ticket
exists per version:

```bash
curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/task/tasks/$KANEO_PROJECT_ID" \
  | jq -r '.[] | select(.title | startswith("[release]") and contains("{version}"))'
<!-- verify this list endpoint against the deployed Kaneo version -->
```

---

## Go/No-Go Assessment

Runs after QA (`staging-qa:passed`) and Security (`staging-sec:passed`) complete.

### Read all inputs

```bash
# Read release ticket for all sign-offs
curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/task/{release-ticket-id}"

# Read QA performance results from QA pod comment
# Read Security scan results from Security pod comment

# Read k6 results (from QA pod)
# Read ZAP staging report (from Security pod)
```

### Structured go/no-go report

Post as comment on release ticket:

```markdown
## Staging Go/No-Go Assessment
**Release Manager** | {timestamp}

### Validation results
| Check | Result | Detail |
|-------|--------|--------|
| QA performance (k6) | ✅ PASS / ❌ FAIL | p99: {X}ms (threshold: 500ms) |
| Error rate | ✅ PASS / ❌ FAIL | {X}% (threshold: <1%) |
| Security scan (ZAP) | ✅ PASS / ❌ FAIL | {N} findings: {summary} |
| All UAT sign-offs | ✅ PASS / ❌ FAIL | qa ✓ / security ✓ / po ✓ |
| RC versions eliminated | ✅ PASS / ❌ FAIL | All services on full version |
| Staging health gate | ✅ PASS / ❌ FAIL | All pods healthy |

### Decision: ✅ GO / ❌ NO-GO

### Reason (if NO-GO)
{Specific reason — which check failed and why it blocks}

### Suggestions (if NO-GO)
**Option A:** {specific fix — estimated effort}
→ Re-promote after fix, re-run staging validation

**Option B:** {alternative approach}
→ {consequence}

**Option C:** Accept risk
→ {what the risk is, likelihood, impact}
→ Requires explicit approval

### Awaiting your decision
```

Apply `rm:go` status and notify n8n if GO:
```bash
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X PATCH "$KANEO_URL/api/task/{release-ticket-id}" \
  -H "Content-Type: application/json" \
  -d '{"status": "rm-go"}'
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X POST "$KANEO_URL/api/task/{release-ticket-id}/comments" \
  -H "Content-Type: application/json" \
  -d '{"content": "RM Go applied — ready for /release-production"}'
<!-- verify both paths/payloads against the deployed Kaneo version -->
```

Signal n8n: `{"status": "rm:go", "task_id": "$TASK_ID"}`

---

## Production Monitoring

Runs after smoke tests pass. Default window: 30 minutes (read from release ticket).

### Metrics to monitor

Poll Grafana every 2 minutes via API or CLI:

```bash
# Error rate (last 5 min)
curl "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" \
  -d 'query=rate(http_requests_total{status=~"5.."}[5m])/rate(http_requests_total[5m])'

# GraphQL p99 latency (last 5 min)
curl "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" \
  -d 'query=histogram_quantile(0.99, rate(graphql_request_duration_seconds_bucket[5m]))'

# Pod restarts (last 10 min)
curl "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" \
  -d 'query=increase(kube_pod_container_status_restarts_total{namespace="production"}[10m])'

# CPU usage (avg over production namespace)
curl "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query" \
  -d 'query=avg(rate(container_cpu_usage_seconds_total{namespace="production"}[5m]))'
```

Compare each metric against thresholds in the release ticket.

---

## Incident Report

When a threshold is breached:

```markdown
## Production Incident Report
**Release Manager** | {timestamp} | v{X}.{Y}.{Z}

### Incident summary
**Metric breached:** {metric name}
**Current value:** {X} (threshold: {Y})
**Duration above threshold:** {N} minutes
**Trend:** {worsening / stable / improving}

### Affected services
{list of services showing elevated metrics}

### Likely cause
{assessment based on metrics — which service, which endpoint, correlation with deployment}

### User impact
{estimated user-facing impact}

### Recommended action
**Option A (recommended):** Rollback to v{X}.{Y}.{Z-1}
- Command: argocd rollback {project}-{service}-production
- Risk: {minutes} downtime during rollback
- Confidence: high — known stable baseline

**Option B:** Investigate and hotfix
- Estimated time to fix: {X} minutes
- Risk: continued user impact during investigation
- Suitable if: the issue is isolated to {specific service/endpoint}

**Option C:** Monitor for {X} more minutes
- Suitable if: trend is improving
- Risk: continued degradation if trend reverses

### Awaiting your decision
```

Post on release ticket and signal n8n for immediate escalation:
```json
{"status": "incident", "severity": "high", "metric": "{metric}", "value": "{X}", "task_id": "$TASK_ID"}
```

---

## Window Clean — Release Confirmation

When monitoring window ends without incident:

```bash
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X PATCH "$KANEO_URL/api/task/{release-ticket-id}" \
  -H "Content-Type: application/json" \
  -d '{"status": "done"}'
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X POST "$KANEO_URL/api/task/{release-ticket-id}/comments" \
  -H "Content-Type: application/json" \
  -d '{"content": "Release v{X}.{Y}.{Z} confirmed stable.\n\nMonitoring window: {start} to {end} ({N} minutes)\nFinal metrics:\n- Error rate: {X}%\n- GraphQL p99: {X}ms\n- gRPC p99: {X}ms\n- Pod restarts: {N}\n- No incidents during window.\n\nRelease ticket closed (status set to Done). UAT cluster sleeping (no separate staging cluster)."}'
<!-- verify both paths/payloads against the deployed Kaneo version -->
```

Signal n8n: `{"status": "release-confirmed", "version": "v{X}.{Y}.{Z}", "task_id": "$TASK_ID"}`

---

## Behaviour Rules

- Create the release ticket the moment PO's UAT sign-off lands — never at `/release-staging` (too late — QA/Security's UAT labels need it to exist already, and by staging time it must already carry all 3)
- Go/no-go report must include validation table and specific reason if NO-GO — never vague
- Always provide 3 suggestions on NO-GO — never leave Edward without options
- Never apply `rm:go` if any validation check failed — even low-severity findings need explicit acceptance
- Incident reports must include trend direction — "breached" is less useful than "breached and worsening"
- Never auto-rollback — always escalate to Edward with recommendation and await decision
- Monitoring window duration comes from the release ticket — never hardcode 30 min
- Never store the release ticket's IID anywhere static — always look it up fresh by `type::release` label + milestone (exactly one exists per version)
