#!/usr/bin/env bash
# Local port-forwards for the terraform-deployed apps (Tilt does this itself).
#
# Browser / SSO: use the TAILNET column — https://<app>.<tailnet_domain>, served
# by the Tailscale k8s operator (terraform/tailscale-ingress.tf). Every OIDC app
# (argocd, openwebui, litellm, grafana, gitlab, nextcloud) bakes that exact
# origin into its redirect_uri, so logging in through the localhost forward or a
# `tailscale serve` port fails ("redirect_uri mismatch" / "Invalid redirect URL").
#
# The localhost forwards below are for non-browser access only — S3 clients,
# `argocd` CLI, psql, curl — where the Host header doesn't matter.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && set -a && source "$REPO_ROOT/.env" && set +a

# tailnet domain: explicit TF_VAR_tailnet_domain wins, else derive from TS_HOST
DOMAIN="${TF_VAR_tailnet_domain:-}"
[ -z "$DOMAIN" ] && [ -n "${TS_HOST:-}" ] && DOMAIN="${TS_HOST#*.}"
[ -z "$DOMAIN" ] && echo "WARNING: no TF_VAR_tailnet_domain / TS_HOST — TAILNET column blank" >&2

# name:namespace:service:svc-port:local-port:magicdns-slug[:path]
apps=(
  "authentik:authentik:authentik-server:80:9000:authentik"
  "gitlab:gitlab:gitlab-webservice-default:8181:8181:gitlab"
  "minio (API):minio:minio:9000:9002:minio"
  "minio (browser):minio:minio-console:9001:9003:minio-console"
  "n8n:n8n:n8n:5678:5678:n8n"
  "sonarqube:sonarqube:sonarqube-sonarqube:9000:9010:sonarqube"
  "nextcloud:nextcloud:nextcloud:8080:8082:nextcloud"
  "argocd:argocd:argocd-server:80:9001:argocd"
  "grafana:observability:observability-grafana:80:3000:grafana"
  "openwebui:openwebui:openwebui:8080:8080:openwebui"
  "litellm:litellm:litellm:4000:4000:litellm:/ui"
)

# ponytail: `kill 0` signals the whole process group at once — every respawn
# subshell, its `sleep`, and its `kubectl` child. The old per-pid SIGTERM loop
# was slow: `kubectl port-forward` on SIGTERM does a graceful apiserver-stream
# close that blocks on a socket timeout when the SPDY stream is already broken.
# (Script is executed, not sourced — the group is just this script + children.)
trap 'echo; echo "stopping port-forwards..."; trap - EXIT; kill 0' INT TERM EXIT

# ponytail: `kubectl port-forward` drops on idle resets / apiserver blips. Wrap
# each in a respawn loop so it self-heals within ~2s.
for entry in "${apps[@]}"; do
  IFS=':' read -r name ns svc svc_port local_port _ _ <<< "$entry"
  ( while true; do
      kubectl port-forward -n "$ns" "svc/$svc" "${local_port}:${svc_port}" >/dev/null 2>&1
      sleep 2
    done ) &
done

echo "waiting for port-forwards to come up..."
sleep 3

check() {
  curl -sk -o /dev/null -m 3 -w '%{http_code}' "$1" 2>/dev/null || true
}

printf "%-18s %-32s %-8s %-45s %-8s\n" "APP" "LOCALHOST (CLI/debug only)" "STATUS" "TAILNET (browser/SSO)" "STATUS"
for entry in "${apps[@]}"; do
  IFS=':' read -r name ns svc svc_port local_port slug path <<< "$entry"
  local_url="http://localhost:${local_port}${path:-}"
  ts_url=""
  [ -n "$DOMAIN" ] && ts_url="https://${slug}.${DOMAIN}${path:-}"
  printf "%-18s %-32s %-8s %-45s %-8s\n" \
    "$name" "$local_url" "$(check "$local_url")" "$ts_url" "${ts_url:+$(check "$ts_url")}"
done

echo
echo "port-forwards running, Ctrl+C to stop"
wait
