#!/usr/bin/env bash
# ponytail: Tilt normally owns these port-forwards; this is the terraform-only
# equivalent — start them by hand, print URLs, tear down on Ctrl+C. Covers
# every app terraform/*.tf deploys.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && set -a && source "$REPO_ROOT/.env" && set +a

if [ -z "${TS_HOST:-}" ]; then
  _ts=$(command -v tailscale 2>/dev/null || command -v tailscale.exe 2>/dev/null || true)
  [ -n "$_ts" ] && TS_HOST="$("$_ts" status --json 2>/dev/null \
    | grep -o '"DNSName":"[^"]*"' | head -1 \
    | sed 's/"DNSName":"//;s/"//g;s/\.$//' || true)"
fi

# name:namespace:service:svc-port:local-port:ts-port
apps=(
  "authentik:authentik:authentik-server:80:9000:8443"
  "gitlab:gitlab:gitlab-webservice-default:8181:8181:443"
  "minio (API):minio:minio:9000:9002:8446"
  "minio (browser):minio:minio-console:9001:9003:8445"
  "n8n:n8n:n8n:5678:5678:8447"
  "sonarqube:sonarqube:sonarqube-sonarqube:9000:9010:8448"
  "seafile:seafile:seafile:80:8082:8449"
  "argocd:argocd:argocd-server:80:9001:8450"
  "grafana:observability:observability-grafana:80:3000:8451"
  "openwebui:openwebui:openwebui:8080:8080:8452"
  "litellm:litellm:litellm:4000:4000:8453"
)

pids=()
cleanup() {
  echo
  echo "stopping port-forwards..."
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT INT TERM

for entry in "${apps[@]}"; do
  IFS=':' read -r name ns svc svc_port local_port _ <<< "$entry"
  kubectl port-forward -n "$ns" "svc/$svc" "${local_port}:${svc_port}" >/dev/null 2>&1 &
  pids+=("$!")
done

echo "waiting for port-forwards to come up..."
sleep 3

check() {
  curl -sk -o /dev/null -m 3 -w '%{http_code}' "$1" 2>/dev/null || true
}

printf "%-20s %-30s %-10s %-45s %-10s\n" "APP" "LOCAL (port-forward)" "STATUS" "TAILSCALE" "STATUS"
for entry in "${apps[@]}"; do
  IFS=':' read -r name ns svc svc_port local_port ts_port <<< "$entry"
  local_url="http://localhost:${local_port}"
  ts_url="https://${TS_HOST}:${ts_port}"
  printf "%-20s %-30s %-10s %-45s %-10s\n" \
    "$name" "$local_url" "$(check "$local_url")" "$ts_url" "$(check "$ts_url")"
done

echo
echo "port-forwards running, Ctrl+C to stop"
wait
