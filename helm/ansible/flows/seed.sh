#!/usr/bin/env bash
# seed.sh — upserts the SDLC n8n flows via the n8n public REST API.
#
# Invoked by the ansible runner (helm/ansible/playbooks/n8n.yml), and by hand:
#
#   N8N_URL=http://localhost:5678 N8N_API_KEY=<key> ./seed.sh
#
# Needs: curl, jq. Idempotent — matches each flow by name, PUTs if it already
# exists, POSTs if not, then activates. Re-run any time to push edits.
# No API key -> logs and exits 0, so a fresh cluster without the key set still
# deploys cleanly.

set -euo pipefail

N8N_URL="${N8N_URL:-http://localhost:5678}"
N8N_API_KEY="${N8N_API_KEY:-}"
FLOW_DIR="${FLOW_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

echo "n8n flow seeder -> $N8N_URL (flows: $FLOW_DIR)"

if [ -z "$N8N_API_KEY" ]; then
  echo "N8N_API_KEY is empty — skipping flow seeding."
  echo "Set TF_VAR_n8n_api_key in .env (create the key in n8n Settings -> API Keys) and redeploy."
  exit 0
fi

api() { curl -sf -H "X-N8N-API-KEY: $N8N_API_KEY" "$@"; }

echo "Waiting for n8n..."
for i in $(seq 1 30); do
  if curl -sf "$N8N_URL/healthz" >/dev/null 2>&1; then echo "  ready"; break; fi
  echo "  attempt $i/30..."; sleep 5
done

# Fail loud on a bad key — otherwise `set -e` kills the script mid-pipe and the
# Job just says "backoff limit reached" with no reason.
probe=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows?limit=1")
if [ "$probe" = 401 ] || [ "$probe" = 403 ]; then
  echo "ERROR: n8n rejected the API key (HTTP $probe)."
  echo "The key in TF_VAR_n8n_api_key is gone or invalid (n8n data reset, or key deleted)."
  echo "Create a fresh one in n8n Settings -> API Keys, update .env, redeploy."
  exit 1
fi
[ "$probe" = 200 ] || { echo "ERROR: GET /api/v1/workflows -> HTTP $probe"; exit 1; }

# name -> id map of what's already there (paginate; API caps limit at 250)
echo "Fetching existing workflows..."
EXISTING=$(mktemp)
cursor=""
: > "$EXISTING"
while :; do
  page=$(api "$N8N_URL/api/v1/workflows?limit=250${cursor:+&cursor=$cursor}")
  echo "$page" | jq -r '.data[] | [.name, .id] | @tsv' >> "$EXISTING"
  cursor=$(echo "$page" | jq -r '.nextCursor // empty')
  [ -z "$cursor" ] && break
done
echo "  $(wc -l < "$EXISTING") present"

id_for() { awk -F'\t' -v n="$1" '$1==n{print $2; exit}' "$EXISTING"; }

CREATED=0; UPDATED=0; FAILED=0
for flow_path in "$FLOW_DIR"/F-*.json; do
  [ -f "$flow_path" ] || continue
  name=$(jq -r '.name // "unknown"' "$flow_path")
  # public API rejects unknown top-level props (id, active, tags, pinData, ...)
  body=$(jq '{name, nodes, connections, settings: (.settings // {})}' "$flow_path")
  id=$(id_for "$name")

  resp=$(mktemp)
  if [ -n "$id" ]; then
    printf '  update %s ... ' "$name"
    code=$(curl -s -o "$resp" -w '%{http_code}' \
      -X PUT "$N8N_URL/api/v1/workflows/$id" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
      --data-binary "$body")
    ok_codes="200"
    verb=UPDATED
  else
    printf '  create %s ... ' "$name"
    code=$(curl -s -o "$resp" -w '%{http_code}' \
      -X POST "$N8N_URL/api/v1/workflows" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
      --data-binary "$body")
    ok_codes="200 201"
    verb=CREATED
  fi

  if echo "$ok_codes" | grep -qw "$code"; then
    id=$(jq -r '.id // empty' "$resp")
    echo "OK (id: ${id:-$id})"
    [ "$verb" = CREATED ] && CREATED=$((CREATED+1)) || UPDATED=$((UPDATED+1))
    if [ -n "$id" ]; then
      api -X POST "$N8N_URL/api/v1/workflows/$id/activate" >/dev/null 2>&1 \
        && echo "    active" || echo "    activation failed — activate manually in the UI"
    fi
  else
    echo "FAILED (HTTP $code)"
    jq . "$resp" 2>/dev/null || cat "$resp"
    FAILED=$((FAILED + 1))
  fi
  rm -f "$resp"
done

rm -f "$EXISTING"
echo "Done: $CREATED created, $UPDATED updated, $FAILED failed."
[ "$FAILED" -eq 0 ]
