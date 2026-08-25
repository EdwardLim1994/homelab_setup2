#!/usr/bin/env bash
# ponytail: one place listing every app's tailnet port -> local port-forward
# mapping, instead of remembering/retyping `tailscale serve` per app.
set -euo pipefail

# https-port:local-port
apps=(
  "8443:9000"  # authentik
  "8444:8181"  # gitlab
  "8446:9002"  # minio S3 API
  "8445:9003"  # minio browser UI/WebUI (separate port on this build)
  "8447:5678"  # n8n
  "8448:9010"  # sonarqube
  "8449:8082"  # seafile
  "8450:9001"  # argocd
)

for entry in "${apps[@]}"; do
  https_port="${entry%%:*}"
  local_port="${entry##*:}"
  echo "serving https://\$(tailscale-hostname):${https_port} -> 127.0.0.1:${local_port}"
  tailscale serve --bg --https="${https_port}" "http://127.0.0.1:${local_port}"
done

tailscale serve status
