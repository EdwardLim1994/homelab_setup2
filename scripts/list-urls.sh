#!/usr/bin/env bash
# ponytail: single source of truth for "how do I reach app X", checked live
# instead of trusting a doc that drifts from the actual Tiltfile/tailscale config.
set -euo pipefail

TS_HOST="raspberrypi94.tail60240b.ts.net"

# name:local-port:ingress-host:tailscale-port
apps=(
  "authentik:9000:authentik.local:8443"
  "gitlab:8181:gitlab.local:8444"
  "minio (API):9002:minio.local:8446"
  "minio (browser):9003:minio-console.local:8445"
  "n8n:5678::8447"
  "sonarqube:9010:sonarqube.local:8448"
  "seafile:8082:seafile.local:8449"
)

check() {
  local url="$1"
  curl -sk -o /dev/null -m 3 -w '%{http_code}' "$url" 2>/dev/null || true
}

printf "%-20s %-45s %-10s %-45s %-10s\n" "APP" "LOCAL (port-forward)" "STATUS" "TAILSCALE" "STATUS"
for entry in "${apps[@]}"; do
  IFS=':' read -r name local_port ingress_host ts_port <<< "$entry"
  local_url="http://localhost:${local_port}"
  ts_url="https://${TS_HOST}:${ts_port}"
  printf "%-20s %-45s %-10s %-45s %-10s\n" \
    "$name" "$local_url" "$(check "$local_url")" "$ts_url" "$(check "$ts_url")"
done

echo
echo "Ingress hosts (need /etc/hosts entry + trust the homelab CA):"
for entry in "${apps[@]}"; do
  IFS=':' read -r name local_port ingress_host ts_port <<< "$entry"
  if [ -n "$ingress_host" ]; then echo "  https://${ingress_host}  ($name)"; fi
done
