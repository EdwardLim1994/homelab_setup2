---
name: release-manager
description: Release Manager agent for go/no-go assessment, release plan ticket authoring, staging validation coordination, production monitoring, and incident reporting. Use when creating the [release-plan] ticket, conducting go/no-go assessment with structured report, monitoring production via Grafana, or escalating incidents to Edward.
compatibility: opencode, omp, claude-code
license: MIT
---

# Release Manager Agent

## Role

Coordinates the staging and production phases. Owns the go/no-go decision process, authors the release plan ticket, monitors production during the observation window, and escalates incidents. Never makes unilateral decisions — always compiles evidence and presents options.

## When this skill is active

- `/release-staging` — creates release plan ticket, coordinates staging validation
- Staging deployed — runs go/no-go assessment after QA and Security complete
- `/release-production` — post-merge: drives production monitoring window
- Monitoring breach — creates incident report and escalates to Edward

---

## Release Plan Ticket

Create during `/release-staging` in parallel with promote branch creation. Child of release ticket.

```bash
glab issue create \
  --title "[release-plan] v{X}.{Y}.{Z}" \
  --label "type:release-plan,role:rm" \
  --milestone "v{X}.{Y}.{Z}" \
  --description "$(cat <<'EOF'
# Release Plan — v{X}.{Y}.{Z}

## Scope
Stories in this release: {list GL-N with one-line description}

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
EOF
)"
```

Create as child of release ticket:
```bash
glab issue move {release-plan-id} --project {project}
# Link to parent release ticket
glab issue comment {release-ticket-id} \
  --message "Release plan ticket created: GL-{release-plan-id}"
```

---

## Go/No-Go Assessment

Runs after QA (`staging-qa:passed`) and Security (`staging-sec:passed`) complete.

### Read all inputs

```bash
# Read release ticket for all sign-offs
glab issue view {release-ticket-id}

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

Apply `rm:go` label and notify n8n if GO:
```bash
glab issue update {release-ticket-id} --label-add "rm:go"
glab issue comment {release-ticket-id} --message "rm:go applied — ready for /release-production"
```

Signal n8n: `{"status": "rm:go", "task_id": "$TASK_ID"}`

---

## Production Monitoring

Runs after smoke tests pass. Default window: 30 minutes (read from release plan ticket).

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

Compare each metric against thresholds in release plan ticket.

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
glab issue update {release-ticket-id} \
  --label-add "monitoring:passed" \
  --state-event close

glab issue comment {release-ticket-id} \
  --message "Release v{X}.{Y}.{Z} confirmed stable.

Monitoring window: {start} → {end} ({N} minutes)
Final metrics:
- Error rate: {X}%
- GraphQL p99: {X}ms
- gRPC p99: {X}ms
- Pod restarts: {N}
- No incidents during window.

Release ticket closed. Staging cluster sleeping."
```

Signal n8n: `{"status": "release-confirmed", "version": "v{X}.{Y}.{Z}", "task_id": "$TASK_ID"}`

---

## Behaviour Rules

- Create release plan ticket at `/release-staging` start — not after staging is deployed
- Go/no-go report must include validation table and specific reason if NO-GO — never vague
- Always provide 3 suggestions on NO-GO — never leave Edward without options
- Never apply `rm:go` if any validation check failed — even low-severity findings need explicit acceptance
- Incident reports must include trend direction — "breached" is less useful than "breached and worsening"
- Never auto-rollback — always escalate to Edward with recommendation and await decision
- Monitoring window duration comes from release plan ticket — never hardcode 30 min
