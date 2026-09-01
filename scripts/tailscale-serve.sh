#!/usr/bin/env bash
# ponytail: one place listing every app's tailnet port -> local port-forward
# mapping, instead of remembering/retyping `tailscale serve` per app.
set -euo pipefail

# https-port:local-port
apps=(
  "8443:9000"  # authentik
  "443:8181"   # gitlab — must be the tailnet's standard 443: the GitLab
               # Helm chart has no non-standard-port support in its generated
               # external URL, so the Web IDE OAuth callback breaks on any
               # other port.
  "8446:9002"  # minio S3 API
  "8445:9003"  # minio browser UI/WebUI (separate port on this build)
  "8447:5678"  # n8n
  "8448:9010"  # sonarqube
  "8449:8082"  # seafile
  "8450:9001"  # argocd
  "8451:3000"  # grafana
  "8452:8080"  # openwebui
  "8453:4000"  # litellm
)

for entry in "${apps[@]}"; do
  https_port="${entry%%:*}"
  local_port="${entry##*:}"
  echo "serving https://\$(tailscale-hostname):${https_port} -> 127.0.0.1:${local_port}"
  tailscale serve --bg --https="${https_port}" "http://127.0.0.1:${local_port}"
done

tailscale serve status
