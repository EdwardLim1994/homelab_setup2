#!/usr/bin/env bash
# ponytail: single source of truth for "how do I reach app X", checked live
# instead of trusting a doc that drifts from the actual Tiltfile/tailscale config.
set -euo pipefail

# source .env for TS_HOST (per-device, gitignored); tailscale detection as fallback
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && set -a && source "$REPO_ROOT/.env" && set +a

if [ -z "${TS_HOST:-}" ]; then
  _ts=$(command -v tailscale 2>/dev/null || command -v tailscale.exe 2>/dev/null || true)
  [ -n "$_ts" ] && TS_HOST="$("$_ts" status --json 2>/dev/null \
    | grep -o '"DNSName":"[^"]*"' | head -1 \
    | sed 's/"DNSName":"//;s/"//g;s/\.$//' || true)"
fi
if [ -z "${TS_HOST:-}" ]; then
  echo "WARNING: TS_HOST not set. Add 'TS_HOST=<your-tailscale-hostname>' to .env" >&2
fi

# name:local-port:ingress-host:tailscale-port[:path]  (path optional, e.g. /ui)
apps=(
  "authentik:9000:authentik.local:8443"
  "gitlab:8181:gitlab.local:443"
  "minio (API):9002:minio.local:8446"
  "minio (browser):9003:minio-console.local:8445"
  "n8n:5678::8447"
  "sonarqube:9010:sonarqube.local:8448"
  "seafile:8082:seafile.local:8449"
  "argocd:9001:argocd.local:8450"
  "grafana:3000:grafana.local:8451"
  "openwebui:8080:openwebui.local:8452"
  "litellm:4000::8453:/ui"
  "nx-cloud:8086:nx-cloud.local:8454"
)

check() {
  local url="$1"
  curl -sk -o /dev/null -m 3 -w '%{http_code}' "$url" 2>/dev/null || true
}

printf "%-20s %-45s %-10s %-45s %-10s\n" "APP" "LOCAL (port-forward)" "STATUS" "TAILSCALE" "STATUS"
for entry in "${apps[@]}"; do
  IFS=':' read -r name local_port ingress_host ts_port path <<< "$entry"
  local_url="http://localhost:${local_port}${path:-}"
  ts_url="https://${TS_HOST}:${ts_port}${path:-}"
  printf "%-20s %-45s %-10s %-45s %-10s\n" \
    "$name" "$local_url" "$(check "$local_url")" "$ts_url" "$(check "$ts_url")"
done

echo
echo "Ingress hosts (need /etc/hosts entry + trust the homelab CA):"
for entry in "${apps[@]}"; do
  IFS=':' read -r name local_port ingress_host ts_port <<< "$entry"
  if [ -n "$ingress_host" ]; then echo "  https://${ingress_host}  ($name)"; fi
done
