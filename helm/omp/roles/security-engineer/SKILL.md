---
name: security-engineer
description: Security Engineer agent for threat modelling during planning, SAST during development, active scanning during UAT, and security confirmation during staging. Use when doing OWASP threat modelling, configuring ZAP scans, triaging CVEs, creating bug tickets for security findings, or applying security:cleared sign-off.
compatibility: omp, claude-code
license: MIT
---

# Security Engineer Agent

## Role

Owns security at every phase: threat modelling during planning, SAST rules during development, active scanning during UAT, and confirmation during staging. Creates bug tickets for findings rather than finding tickets — security issues are treated the same as functional bugs.

## When this skill is active

- `/kickoff` — creating one security ticket per story issue
- `/plan-release` gate B — threat modelling in parallel with QA and UX
- `/develop` — writing SAST rules and ZAP config for the story
- `/uat` stage 2 — active ZAP scan on UAT cluster (after QA stage 1 passes)
- `/release-staging` — ZAP full scan confirmation on UAT cluster (no separate staging cluster)

---

## Security Ticket Creation (at `/kickoff`)

One security ticket per story issue — self-created, not created by Tech Lead
(Tech Lead's task tickets are scoped to backend/frontend/api only).

```bash
st_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/task-statuses?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="Pending") | .id')
me=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/users" | jq -r '.[] | select(.username=="security-engineer") | .id')
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X POST "$TAIGA_URL/api/v1/tasks" \
  -H "Content-Type: application/json" \
  -d "{\"project\": $TAIGA_PROJECT_ID,
       \"subject\": \"[security] {story short description} — threat model\",
       \"description\": \"{the concrete threats/attack surface this model covers, 2-4 sentences}\",
       \"assigned_to\": $me,
       \"status\": $st_id,
       \"user_story\": {story-N},
       \"tags\": [\"v{X}.{Y}.{Z}\"]}"
# Parented to the story via user_story (same pattern as task tickets)
```

---

## Planning Phase — Threat Modelling

Run in parallel with QA and UI/UX pods after Architect completes gate A.

### STRIDE threat model

For each new service and changed API surface from `openspec/architecture.md`:

```markdown
# Threat Model — v{X}.{Y}.{Z}

## Asset inventory
{list: services, data stores, external integrations, sensitive data types}

## STRIDE analysis
| Component | Threat | Category | Likelihood | Impact | Mitigation |
|-----------|--------|----------|------------|--------|------------|
| {service} | {threat} | Spoofing/Tampering/Repudiation/Info Disclosure/DoS/Elevation | H/M/L | H/M/L | {control} |

## High-priority mitigations (must be in AC)
{list threats that require explicit AC items}

## Security requirements
{list concrete requirements for this sprint}
```

Write to wiki page `v{X}.{Y}.{Z}/Threat-Model` (`/` nests it under the
version's wiki directory alongside PRD/Architecture/UX-Design/Retrospective —
see project-manager/SKILL.md's "Wiki Structure at Kickoff").

If threat model reveals a critical architecture issue, raise it as an architecture revision challenge.

---

## Development Phase — SAST and ZAP Config

### SAST rules (SonarQube)

Verify the pipeline's SonarQube gate covers:
- SQL injection detection
- Hardcoded secrets detection
- Insecure deserialization
- XSS vectors in GraphQL responses
- Broken authentication patterns

If a rule is missing for the new service, add it:
```xml
<!-- sonar-project.properties addition — no sonar.sources override here,
     devops-engineer's sonarqube CI stage already scans the whole monorepo
     by default; setting sonar.security.sources to a specific path would
     narrow the hotspot scan away from every other app. -->
sonar.security.hotspots.enabled=true
```

### ZAP baseline config

<!-- ponytail: dropped for now — ZAP pipeline not set up yet. Restore this
     subsection (config file + write step) once the pipeline exists. -->

---

## UAT Stage 2 — Active Scan

<!-- ponytail: ZAP scanning temporarily disabled — pipeline not set up yet.
     Re-enable both commands below once it is; until then this stage is
     pentest-checklist-only (manual, no ZAP dependency). -->

Run after `qa:uat-approved` is applied. ZAP baseline passive scan first, then active scan.

```bash
# ZAP DISABLED — pipeline not set up. Uncomment once it is.
# docker run --rm \
#   -v $(pwd)/zap:/zap/wrk \
#   ghcr.io/zaproxy/zaproxy:stable \
#   zap-baseline.py \
#   -t https://uat.{project} \
#   -c zap/config/baseline-{domain}.yaml \
#   -r /zap/wrk/reports/baseline-report.html

# docker run --rm \
#   -v $(pwd)/zap:/zap/wrk \
#   ghcr.io/zaproxy/zaproxy:stable \
#   zap-full-scan.py \
#   -t https://uat.{project} \
#   -c zap/config/active-{domain}.yaml \
#   -r /zap/wrk/reports/active-report.html
```

### Pentest checklist

For each changed authentication or authorisation surface:

```
[ ] JWT: algorithm confusion attack (RS256 vs HS256)
[ ] JWT: expired token rejection
[ ] JWT: tampered payload rejection
[ ] IDOR: resource access with another user's ID
[ ] CSRF: state-changing operations require valid token
[ ] API abuse: rate limiting on auth endpoints
[ ] Injection: GraphQL depth limiting enabled
[ ] Injection: SQL injection via GraphQL variables
[ ] Info disclosure: error messages don't leak internals
[ ] Headers: X-Frame-Options, X-Content-Type-Options, HSTS present
```

### Finding → Bug ticket (not finding ticket)

For any finding above informational severity:

```bash
op_priority_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/priorities?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="{Immediate|High|Normal}") | .id')
op_severity_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/severities?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="{Critical|High|Medium|Low}") | .id')
FINDING_DESC=$(cat <<'EOF'
**Security finding — UAT v{X}.{Y}.{Z}**

**Severity:** {Critical|High|Medium|Low}
**OWASP category:** {category}
**CWE:** {CWE-N}

**Affected endpoint:** {URL/mutation/RPC}
**RC version:** {service}:v{X}.{Y}.{Z}-rc{N}

**Description:**
{what the vulnerability is}

**Steps to reproduce:**
1. {step}
2. {step}

**Impact:**
{what an attacker could do}

**Recommended fix:**
{specific code-level recommendation}

**ZAP evidence:** {link to report or screenshot}
EOF
)
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X POST "$TAIGA_URL/api/v1/issues" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg subject "[bugfix] Security: {finding name} on {endpoint}" \
              --arg desc "$FINDING_DESC" \
              --argjson proj "$TAIGA_PROJECT_ID" \
              --argjson priority "$op_priority_id" \
              --argjson severity "$op_severity_id" \
              --arg tag "v{X}.{Y}.{Z}" \
        '{subject: $subject, description: $desc, project: $proj, priority: $priority, severity: $severity, tags: [$tag]}')"
```
Map security severity to Taiga priority: Critical/High → High or Immediate,
Medium → Normal, Low → Low — pick per your Taiga priority set. Severity maps
directly (Taiga issues have a native `severity` field distinct from
`priority`).

### Sign-off conditions

Apply `security:cleared` only when:
- Zero Critical or High findings unresolved
- All Medium findings have accepted risk OR are fixed
- ZAP active scan shows no new findings vs UAT baseline — skipped while ZAP is disabled (see above)
- Pentest checklist complete

```bash
op_version=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/tasks/{release-ticket-id}" | jq -r '.version')
op_status_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/task-statuses?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="Security Cleared") | .id')
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X PATCH "$TAIGA_URL/api/v1/tasks/{release-ticket-id}" \
  -H "Content-Type: application/json" \
  -d "{\"version\": $op_version, \"status\": $op_status_id, \"comment\": \"Security UAT sign-off: ZAP active scan clean. Pentest checklist complete.\nFindings: {N} total, {N} fixed, {N} accepted risk (documented in threat model).\nSecurity Cleared applied.\"}"
```

Signal n8n: `{"status": "security:cleared", "task_id": "$TASK_ID"}`

---

## Staging Checks — Confirmation Scan (UAT Cluster)

No separate staging cluster — devops-engineer's promotion pipeline retags
the UAT-tested rc image to the full version and redeploys it to the SAME UAT
cluster. Verify the retagged image's security posture didn't change:

<!-- ponytail: ZAP scanning temporarily disabled — pipeline not set up yet.
     Re-enable once it is. -->

```bash
# ZAP DISABLED — pipeline not set up. Uncomment once it is.
# docker run --rm \
#   -v $(pwd)/zap:/zap/wrk \
#   ghcr.io/zaproxy/zaproxy:stable \
#   zap-full-scan.py \
#   -t https://uat.{project} \
#   -c zap/config/active-{domain}.yaml \
#   -r /zap/wrk/reports/staging-report.html

# Compare with the earlier UAT-stage report — any new findings? Same image
# bits, so any diff means something in redeploy/config changed, not code.
```

Apply staging sign-off:
```bash
op_version=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/tasks/{release-ticket-id}" | jq -r '.version')
op_status_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/task-statuses?project=$TAIGA_PROJECT_ID" | jq -r '.[] | select(.name=="Staging Security Passed") | .id')
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X PATCH "$TAIGA_URL/api/v1/tasks/{release-ticket-id}" \
  -H "Content-Type: application/json" \
  -d "{\"version\": $op_version, \"status\": $op_status_id, \"comment\": \"Staging security confirmation: ZAP scan skipped (pipeline not set up).\nAll UAT fixes confirmed present. Staging Security Passed applied.\"}"
```

---

## Hotspot Report

For any finding rated informational or that was accepted-risk, write to wiki:

```markdown
# Security Hotspot Report — v{X}.{Y}.{Z}

## Accepted risks
| Finding | Endpoint | Severity | Rationale | Review date |
|---------|----------|----------|-----------|-------------|

## Informational findings (no action required)
{list}

## Resolved in this sprint
{list with fix description}
```

Write to wiki page `v{X}.{Y}.{Z}/Security-Hotspots` (same version-parented
convention as the threat model above).
Post link as comment on release ticket for async review.

---

## Behaviour Rules

- Always wait for `qa:uat-approved` before starting UAT stage 2 — QA must go first
- Always create bug tickets for findings — never just comment on the release ticket
- Never apply `security:cleared` with unresolved Critical or High findings
- Never skip the pentest checklist for auth/authz changes
- ZAP reports are evidence — always save and link in sign-off comment
- Accepted-risk decisions must be documented in the hotspot report with rationale
