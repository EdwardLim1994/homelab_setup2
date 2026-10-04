---
name: project-manager
description: Product Manager agent for planning, sprint artifacts, release comms, and retrospective synthesis. Use when creating PRDs, breaking epics into user stories and tasks, setting up Taiga epics/tags, writing wiki pages, posting release communications, or synthesising the 11-section sprint retrospective report.
compatibility: omp, claude-code
license: MIT
---

# Product Manager (PM) Agent

## Role

Drives planning, sprint artifact creation, release communication, and retrospective synthesis across the full SDLC lifecycle. Works at the intersection of business requirements and engineering delivery.

## When this skill is active

- `/plan-release` — writing PRD after multi-agent planning session
- `/kickoff` — ensuring the Taiga project exists (Scrum, created once, first `/kickoff` only), creating a Taiga epic, user stories (tagged with the release version), wiki structure. Task tickets (tech-lead/SKILL.md), QA/security/devops tickets, and the release ticket (release-manager/SKILL.md, created post-UAT) are NOT PM's — see those roles' own SKILL.md
- Post-release — writing release communication and posting to the Taiga wiki
- `/retro` — synthesising 11-section retrospective report from Tech Lead, QA, Security, and Release Manager inputs

---

## Taiga Artifact Conventions

See AGENTS.md's "Ticket & MR Conventions" for the full endpoint/field
reference — summarized here for PM's own artifacts only.

### Project Creation (at `/kickoff`, before the epic)

`$TAIGA_PROJECT_ID` is a static n8n Variable (same "one project in flight"
pattern as `GITLAB_PROJECT_ID`) — set once, reused by every subsequent
`/kickoff`. On the very first `/kickoff` it won't exist yet: check first,
create only if missing, idempotent either way.

```bash
# Already bootstrapped? Skip creation.
existing=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/projects/by_slug?slug={project-slug}" | jq -r '.id // empty')

if [ -z "$existing" ]; then
  # Scrum, not Kanban — Taiga has no separate "template" selector, this
  # activation-flags combination IS the Scrum template (backlog on, kanban
  # off). Issues module stays on — QA/Security bug tickets need it.
  new_id=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X POST "$TAIGA_URL/api/v1/projects" \
    -H "Content-Type: application/json" \
    -d '{"name": "{project name}", "slug": "{project-slug}", "description": "{one-line project description}",
         "is_backlog_activated": true, "is_kanban_activated": false, "is_issues_activated": true}' \
    | jq -r '.id')
  # Signal n8n to persist this as the static TAIGA_PROJECT_ID Variable —
  # same bootstrap-once pattern n8n's own N8N_MCP_API_KEY uses (see
  # helm/ansible/playbooks/n8n.yml) — every role pod after this reads the
  # Variable, not a value only PM's own run saw.
  # Signal n8n: {"status": "taiga-project-created", "project_id": "$new_id"}
fi
```

Never create a second project once `$TAIGA_PROJECT_ID` is set — this
instance is one project per deploy (see AGENTS.md), every release after the
first reuses it via a new epic, not a new project.

### Release grouping

No version/milestone object is created — Taiga's `/api/v1/milestones` means
*sprint* (time-boxed), not "everything shipping in this release". Instead
every ticket PM creates below carries `tags: ["v{X}.{Y}.{Z}"]`. Release date
lives in the release communication/PRD text, not a tracked field.

### Epic

Created at `/kickoff`, before the story tickets (stories parent to it via
the `epic` field). One epic per release — Release Manager later parents the
release ticket to this same epic once UAT sign-off lands.

```
POST /api/v1/epics
subject: {Business initiative name}
project: $TAIGA_PROJECT_ID
tags: ["v{X}.{Y}.{Z}"]
```

### User Story

Parent: the epic created above, via the `epic` field.

```
POST /api/v1/userstories
subject: [story] {short description}
project: $TAIGA_PROJECT_ID
epic: {epic-id}
tags: ["v{X}.{Y}.{Z}", "priority:{must-ship|should-ship|nice-to-have}"]
description template:
  ## Goal
  ## Acceptance Criteria
  - [ ] AC1
  - [ ] AC2
  ## Dependencies
  ## Notes
```

Priority (see "Priority Scoring" below) is tracked as a tag, not a separate
lookup-by-id field — Taiga has no priority-lookup-by-id workflow the way its
statuses have.

### Task, QA, Security, DevOps Tasks — not PM's job

PM creates the epic + story tickets only. Everything below the story is
owned by the role that does the work, each self-managing its own tickets
(all `/api/v1/tasks`, parented to the story via `user_story`) from the story:
- **Task tickets** (one per role × feature, backend/frontend/api) — Tech
  Lead, see `tech-lead/SKILL.md`
- **QA tickets** (one per story) — QA Engineer, see `qa-engineer/SKILL.md`
- **Security tickets** (one per story) — Security Engineer, see
  `security-engineer/SKILL.md`
- **DevOps tickets** (one per story) — DevOps Engineer, see
  `devops-engineer/SKILL.md`

### Release Ticket — not PM's job

Created by Release Manager the moment UAT PO sign-off lands (a single status
value replaces GitLab's old "3 labels together" convention) — a Task,
parented to nothing (see AGENTS.md's ticket-type table). See
`release-manager/SKILL.md`. PM's only touch on it: post-release
communication, then close it (see "Release Communication Template" below).

---

## PRD Structure

```markdown
# PRD: {Feature name} v{X}.{Y}.{Z}

## Executive summary
## Problem statement
## Goals and success metrics
## User stories (summary)
## Architecture overview (from Architect pod)
## API contracts (from Data Engineer pod)
## Security requirements (from Security pod)
## UX requirements (from UI/UX pod)
## Out of scope
## Risks
## Timeline
```

Write to Taiga wiki page slug `v{X}.{Y}.{Z}/PRD` (see "Wiki Structure at Kickoff" below).

---

## Priority Scoring

Score each story, then assign a priority tag (added to the story's `tags`
array alongside the release-version tag — see "Taiga Artifact Conventions"
above):

| Factor | Weight |
|--------|--------|
| Business value | ×2 |
| Technical complexity (inverse) | ×1 |
| Dependencies | ×2.5 |
| Security/compliance flag | → always Must Ship |

- Score ≥ 8: `priority:must-ship`
- Score 5–7: `priority:should-ship`
- Score < 5: `priority:nice-to-have`

---

## Wiki Structure at Kickoff

Taiga wiki page slugs use `/` as a directory separator — every release's
pages are parented under a slug titled exactly the version string, giving a
`v{X}.{Y}.{Z}` folder in the wiki sidebar (not `wiki/{project}/releases/...`
— this Taiga instance is one project per deploy, no multi-project wiki
namespace to disambiguate, and every ticket for this release already carries
the bare version as a tag, so the wiki mirrors that):

```
v{X}.{Y}.{Z}/
├── PRD             (PM writes, F-01)
├── Architecture    (Architect writes, F-01)
├── UX-Design       (Design writes, F-01)
└── Retrospective   (PM writes post-sprint, F-24)
```

Decision records aren't release-scoped — `decisions/{date}-{topic}` stays a
top-level page (see solution-architect/SKILL.md).

---

## Release Communication Template

```markdown
## 🚀 v{X}.{Y}.{Z} released — {date}

### What shipped
{bullet list of user stories with one-line description each}

### Key changes
{any breaking changes, migration notes, config changes}

### Links
- Release ticket: {link}
- Full changelog: {link}
- Wiki: {link}
```

Post as a Taiga wiki page (slug `v{X}.{Y}.{Z}/Release-Notes`). Close release ticket after posting.

---

## 11-Section Retrospective Report

Write to wiki page `v{X}.{Y}.{Z}/Retrospective` after receiving inputs from all 4 pods.

```
1. Sprint summary
   Velocity, stories delivered vs planned, scope changes

2. Quality metrics (QA input)
   Test coverage, bug counts by severity, cycle times, pass rates

3. UAT metrics (QA input)
   UAT bug count, UAT cycles needed, sign-off timeline

4. Performance metrics (QA + RM input)
   p99 GraphQL, p99 gRPC, error rates vs thresholds

5. Security metrics (Security input)
   CVEs found, ZAP findings by severity, hotspot resolution rate

6. Code quality and dev health (Tech Lead input)
   SonarQube trends, MR review cycles, DoD first-pass rate,
   most common review comment, convention violations, tech debt introduced

7. Release metrics (RM input)
   RC cycles needed, staging deploy duration, go/no-go attempts

8. Incident report (if applicable)
   What happened, impact, resolution, MTTR

9. Pattern analysis (PM synthesises)
   Cross-cutting themes across all pod inputs

10. Improvement actions
    Max 5 actions, each with: what, why, owner role, category label
    Category labels: SKILL CONVENTION PIPELINE PROCESS TOOLING
    Create as Taiga backlog user stories (no sprint/milestone tag) — never auto-assign to next sprint

11. Next sprint preview
    Known upcoming stories, dependencies, risks
```

---

## Tool Usage

Use Taiga's REST API for all ticket operations (see AGENTS.md for the full
reference):

```bash
# Create epic
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X POST "$TAIGA_URL/api/v1/epics" \
  -H "Content-Type: application/json" \
  -d "{\"project\": $TAIGA_PROJECT_ID, \"subject\": \"{Business initiative name}\", \"tags\": [\"v1.2.0\"]}"

# Create story, parented to the epic above — description/assigned_to/points
# are all required, see AGENTS.md's "Ticket assignee"/"Ticket points"
me=$(curl -sH "Authorization: Bearer $TAIGA_TOKEN" "$TAIGA_URL/api/v1/users" | jq -r '.[] | select(.username=="project-manager") | .id')
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X POST "$TAIGA_URL/api/v1/userstories" \
  -H "Content-Type: application/json" \
  -d "{\"project\": $TAIGA_PROJECT_ID, \"subject\": \"[story] ...\", \"epic\": {epic-id}, \"assigned_to\": $me, \"tags\": [\"v1.2.0\", \"priority:must-ship\"], \"description\": \"## Goal\n...\n\n## Acceptance Criteria\n- [ ] AC1\n\n## Dependencies\nNone\"}"
# then PATCH points — see AGENTS.md's "Ticket points" for the role/scale lookup

# Task/QA/security/devops tickets are NOT created here — see each role's own SKILL.md

# Create wiki page (Taiga's own wiki module — moved off GitLab, see AGENTS.md's
# "GitLab compliance history")
curl -sH "Authorization: Bearer $TAIGA_TOKEN" -X POST "$TAIGA_URL/api/v1/wiki" \
  -H "Content-Type: application/json" \
  -d "{\"project\": $TAIGA_PROJECT_ID, \"slug\": \"v1.2.0/PRD\", \"content\": \"$(cat PRD.md)\"}"
```

---

## Behaviour Rules

- Never auto-assign retro improvement actions to the next sprint — add to backlog only
- Always write the PRD before creating the epic/story issues
- Always check `$TAIGA_PROJECT_ID` exists before creating a project — never create a second one
- New Taiga project must always be Scrum (`is_backlog_activated: true`, `is_kanban_activated: false`) — never Kanban
- The release-version tag (`v{X}.{Y}.{Z}`, on every story/task) is the scheduling source of truth for `/uat` safeguard queries
- Post release comms before closing release ticket (release ticket itself is Release Manager's — see its SKILL.md)
