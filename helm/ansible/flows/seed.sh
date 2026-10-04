#!/usr/bin/env bash
# seed.sh — seeds all 28 SDLC n8n flows via n8n REST API
# Flows use Mattermost slash commands for user-invoked phases.
# GitLab/CI events remain as webhooks.
#
# Usage:
#   N8N_URL=http://localhost:5678 N8N_API_KEY=your-key ./seed.sh [--force]

set -euo pipefail

N8N_URL="${N8N_URL:-http://localhost:5678}"
N8N_API_KEY="${N8N_API_KEY:?N8N_API_KEY is required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat << 'SETUP'
================================
n8n SDLC Flow Seeder — Mattermost edition
================================

MATTERMOST SETUP (required before flows work):

1. Create a Bot account in Mattermost:
   System Console → Integrations → Bot Accounts → Add Bot
   Username: sdlc-bot
   Copy the Bot Access Token

2. Add n8n credential:
   n8n → Credentials → New → Mattermost API
   Name: "Mattermost SDLC Bot"
   Access Token: (paste Bot Access Token)
   Base URL: https://mattermost.yourdomain.com

3. Register slash commands in Mattermost:
   Main Menu → Integrations → Slash Commands → Add Slash Command

   Command        → Request URL
   /plan_release  → https://n8n.yourdomain.com/webhook/mm-plan_release
   /kickoff       → https://n8n.yourdomain.com/webhook/mm-kickoff
   /develop       → https://n8n.yourdomain.com/webhook/mm-develop
   /uat           → https://n8n.yourdomain.com/webhook/mm-uat
   /release_staging     → https://n8n.yourdomain.com/webhook/mm-release_staging
   /release_production  → https://n8n.yourdomain.com/webhook/mm-release_production
   /rollback      → https://n8n.yourdomain.com/webhook/mm-rollback
   /rollback_story → https://n8n.yourdomain.com/webhook/mm-rollback_story
   /retro         → https://n8n.yourdomain.com/webhook/mm-retro
   /projects      → https://n8n.yourdomain.com/webhook/mm-projects

   For each command:
     Request method: POST
     Response username: sdlc-bot
     Autocomplete: enabled (add description)

4. Add bot to your SDLC channel:
   /invite @sdlc-bot

5. Set env vars in n8n Settings → Variables:
   MM_SDLC_CHANNEL = your-channel-id  (find in channel URL or API)
   MM_BASE_URL     = https://mattermost.yourdomain.com
   GITLAB_URL, GITLAB_TOKEN, GITLAB_PROJECT_ID
   N8N_WEBHOOK_BASE, GITLAB_WEBHOOK_SECRET
   ARGOCD_URL, ARGOCD_PROJECT
   RELEASE_VERSION (the release ticket itself is looked up dynamically by
   `type::release` label + milestone — never set a static RELEASE_TICKET_ID)

6. Chat with omp (flow F-28) — the sdlc-svc user, the 'ai' channel, the
   outgoing webhook, and the n8n credential are all created by
   playbooks/mattermost.yml:
     scripts/ansible-run.sh mattermost
   Then in the 'ai' channel type:  omp <your question>
   (trigger word 'omp' — mmctl's create-outgoing needs one). First message
   after the omp pod idles waits ~30-120s for scale-up + model load.

7. GitLab group webhook -> n8n F-00 router. Registered automatically by the
   DevOps pod at /kickoff; for bootstrap / disaster recovery run:
     scripts/ansible-run.sh gitlab-webhook
   URL: <n8n>/webhook/gitlab-events, events: Merge requests + Pipelines,
   secret: TF_VAR_gitlab_webhook_secret (same value F-00 verifies against).

SETUP

echo ""

# Wait for n8n
echo "Waiting for n8n to be ready..."
for i in {1..30}; do
  if curl -sf "$N8N_URL/healthz" > /dev/null 2>&1; then
    echo "n8n is ready."
    break
  fi
  echo "  attempt $i/30 ..."
  sleep 5
done

# True upsert: fetch every existing workflow's id+name once, keyed by name,
# so re-running this script always applies edits to the SAME workflow
# instead of bailing out (old behavior) or POSTing a same-name duplicate
# (old --force behavior). n8n's list endpoint pages at 100 by default and
# there are ~29 flows, so one page is enough — pagination added anyway in
# case flows grow past that.
echo "Fetching existing workflows for upsert lookup..."
: > /tmp/n8n-existing.json
CURSOR=""
while :; do
  URL="$N8N_URL/api/v1/workflows?limit=100"
  [ -n "$CURSOR" ] && URL="$URL&cursor=$CURSOR"
  PAGE=$(curl -sf -H "X-N8N-API-KEY: $N8N_API_KEY" "$URL")
  echo "$PAGE" | python3 -c "
import json,sys
d = json.load(sys.stdin)
for wf in d.get('data', []):
    print(wf['name'] + '\t' + str(wf['id']))
" >> /tmp/n8n-existing.json
  CURSOR=$(echo "$PAGE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('nextCursor') or '')")
  [ -z "$CURSOR" ] && break
done
EXISTING_COUNT=$(wc -l < /tmp/n8n-existing.json)
echo "Found $EXISTING_COUNT existing workflow(s)."

SUCCESS=0
FAILED=0
# ponytail: filenames verified against actual webhook `path` values each
# flow uses and what F-00/F-10 actually call by URL — this directory has
# several stale duplicate/renamed leftovers (e.g. F-07-flow.json,
# F-23-revert-mr-merged.json) that do NOT match what the live dispatchers
# call. Don't "fix" a filename here without re-checking the caller's URL.
FLOWS=(
  "F-00-gitlab-event-router.json"
  "F-01-plan-release.json"
  "F-02-kickoff.json"
  "F-03-develop.json"
  "F-04-task-mr-opened.json"
  "F-05-task-mr-merged.json"
  "F-06-dod-check.json"
  "F-07-story-mr-open.json"
  "F-08-story-mr-merged.json"
  "F-09-ci-pipeline.json"
  "F-10-uat.json"
  "F-11-uat-qa.json"
  "F-12-uat-security.json"
  "F-13-uat-po.json"
  "F-14-release-staging.json"
  "F-15-staging-deployed.json"
  "F-16-go-nogo.json"
  "F-17-release-production.json"
  "F-18-release-mr-merged.json"
  "F-19-production-deployed.json"
  "F-20-monitoring-window.json"
  "F-21-rollback.json"
  "F-22-rollback-story.json"
  "F-23-revert-merged.json"
  "F-24-retro.json"
  "F-25-escalate.json"
  "F-26-projects.json"
  "F-27-cluster-lifecycle.json"
  "F-28-chat.json"
  "F-29-flow-progress-sink.json"
  "F-30-flow-progress-poll.json"
  "F-31-spawn-agent-role.json"
)

for flow_file in "${FLOWS[@]}"; do
  flow_path="$SCRIPT_DIR/$flow_file"
  if [ ! -f "$flow_path" ]; then
    echo "  SKIP: $flow_file (not found)"
    continue
  fi
  flow_name=$(python3 -c "import json; print(json.load(open('$flow_path')).get('name','?'))")

  # Look up existing workflow by exact name (tab-separated name<TAB>id lines).
  EXISTING_ID=$(awk -F'\t' -v n="$flow_name" '$1==n {print $2; exit}' /tmp/n8n-existing.json)

  # n8n 2.x public API rejects read-only keys (active, tags, id, ...) on
  # create AND update. Keep only the writable fields either way.
  python3 -c "import json,sys; d=json.load(open('$flow_path')); json.dump({k:d[k] for k in ('name','nodes','connections','settings','staticData') if k in d}, open('/tmp/n8n-seed-body.json','w'))"

  if [ -n "$EXISTING_ID" ]; then
    echo -n "  Updating: $flow_name (id: $EXISTING_ID) ... "
    HTTP_CODE=$(curl -s -o /tmp/n8n-seed-resp.json -w "%{http_code}" \
      -X PUT "$N8N_URL/api/v1/workflows/$EXISTING_ID" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      -H "Content-Type: application/json" \
      -d @/tmp/n8n-seed-body.json)
    if [ "$HTTP_CODE" -eq 200 ]; then
      echo "OK (updated, id: $EXISTING_ID)"
      # ponytail: n8n deactivates a workflow's webhook registration on PUT
      # even when content didn't structurally change — re-activate every
      # update, not just creates, or the workflow silently stops answering
      # its webhook until someone notices.
      curl -sf -X POST "$N8N_URL/api/v1/workflows/$EXISTING_ID/activate" \
        -H "X-N8N-API-KEY: $N8N_API_KEY" > /dev/null 2>&1 \
        && echo "    → activated" || echo "    → activation failed (activate manually)"
      SUCCESS=$((SUCCESS+1))
    else
      echo "FAILED (HTTP $HTTP_CODE)"
      python3 -m json.tool /tmp/n8n-seed-resp.json 2>/dev/null || true
      FAILED=$((FAILED+1))
    fi
  else
    echo -n "  Creating: $flow_name ... "
    HTTP_CODE=$(curl -s -o /tmp/n8n-seed-resp.json -w "%{http_code}" \
      -X POST "$N8N_URL/api/v1/workflows" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      -H "Content-Type: application/json" \
      -d @/tmp/n8n-seed-body.json)
    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
      WF_ID=$(python3 -c "import json; print(json.load(open('/tmp/n8n-seed-resp.json')).get('id','?'))" 2>/dev/null || echo "?")
      echo "OK (created, id: $WF_ID)"
      if [ "$WF_ID" != "?" ]; then
        curl -sf -X POST "$N8N_URL/api/v1/workflows/$WF_ID/activate" \
          -H "X-N8N-API-KEY: $N8N_API_KEY" > /dev/null 2>&1 \
          && echo "    → activated" || echo "    → activation failed (activate manually)"
      fi
      SUCCESS=$((SUCCESS+1))
    else
      echo "FAILED (HTTP $HTTP_CODE)"
      python3 -m json.tool /tmp/n8n-seed-resp.json 2>/dev/null || true
      FAILED=$((FAILED+1))
    fi
  fi
done

echo ""
echo "================================"
echo "Seeding complete: $SUCCESS OK  $FAILED failed"
echo "================================"
echo ""
echo "Slash command → webhook path mapping:"
echo "  /plan_release        → /webhook/mm-plan_release   (F-01)"
echo "  /kickoff             → /webhook/mm-kickoff        (F-02)"
echo "  /develop             → /webhook/mm-develop        (F-03)"
echo "  /uat                 → /webhook/mm-uat            (F-10)"
echo "  /release_staging     → /webhook/mm-release_staging (F-14)"
echo "  /release_production  → /webhook/mm-release_production (F-17)"
echo "  /rollback            → /webhook/mm-rollback       (F-21)"
echo "  /rollback_story      → /webhook/mm-rollback_story (F-22)"
echo "  /retro               → /webhook/mm-retro          (F-24)"
echo "  /projects            → /webhook/mm-projects       (F-26)"
echo ""
echo "GitLab single webhook → /webhook/gitlab-events (F-00)"
echo "(DevOps pod registers this at /kickoff via glab — no manual setup)"
