#!/bin/sh
# render-mermaid.sh <output.png> <mermaid-source-file>
#
# Renders a Mermaid diagram to PNG via the scale-to-zero mermaid-render
# microservice: scales it 0 -> 1, waits for ready, POSTs the Mermaid
# source, saves the PNG response, then ALWAYS scales it back to 0 — same
# PATCH-the-/scale-subresource technique as helm/omp/adapter/server.py's
# waker, but this script also does the scale-down (the adapter never
# does), since this is a single synchronous call, not a shared long-lived
# endpoint that needs idle-timeout tracking.
#
# ponytail: no cross-Job coordination — if two /plan_release runs overlap,
# one Job's scale-down could race another's in-flight render. Acceptable
# at this homelab's scale (sequential gate flow); a reference-counted
# scale manager would be the real fix if this ever becomes a problem.
set -eu

OUT_FILE="$1"
MMD_FILE="$2"

TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
API="https://kubernetes.default.svc"
NS=sdlc
DEPLOY=mermaid-render

api_curl() {
  curl -sk -H "Authorization: Bearer $TOKEN" "$@"
}

scale_down() {
  api_curl -X PATCH -H "Content-Type: application/merge-patch+json" \
    -d '{"spec":{"replicas":0}}' \
    "$API/apis/apps/v1/namespaces/$NS/deployments/$DEPLOY/scale" -o /dev/null || true
}
trap scale_down EXIT

api_curl -X PATCH -H "Content-Type: application/merge-patch+json" \
  -d '{"spec":{"replicas":1}}' \
  "$API/apis/apps/v1/namespaces/$NS/deployments/$DEPLOY/scale" -o /dev/null

# ponytail: 100 x 2s = 200s budget -- minlag/mermaid-cli is a heavy
# (Chromium-bundled) image; a cold pull on a node that's never run it
# before measured ~150s in testing. Once cached node-side this is fast
# (just a digest check, image stays local).
i=0
while [ "$i" -lt 100 ]; do
  READY=$(api_curl "$API/apis/apps/v1/namespaces/$NS/deployments/$DEPLOY" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',{}).get('readyReplicas',0))" 2>/dev/null || echo 0)
  [ "$READY" -ge 1 ] 2>/dev/null && break
  i=$((i + 1))
  sleep 2
done
if [ "$READY" != "" ] && [ "$READY" -lt 1 ] 2>/dev/null; then
  echo "render-mermaid.sh: mermaid-render didn't become ready in time" >&2
  exit 1
fi

HTTP_CODE=$(curl -sk -w '%{http_code}' -o "$OUT_FILE" \
  --data-binary "@$MMD_FILE" \
  "http://$DEPLOY.$NS.svc.cluster.local:4098/render")

if [ "$HTTP_CODE" != "200" ]; then
  echo "render-mermaid.sh: render failed (HTTP $HTTP_CODE)" >&2
  cat "$OUT_FILE" >&2 || true
  exit 1
fi

echo "$OUT_FILE"
