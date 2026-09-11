#!/usr/bin/env bash
# ponytail: single source of truth for "how do I reach app X", checked live.
# Apps are exposed on the tailnet by the Tailscale k8s operator (one MagicDNS
# host per app); the *.local Traefik ingresses are the LAN fallback.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && set -a && source "$REPO_ROOT/.env" && set +a

# tailnet_domain: explicit TF_VAR_tailnet_domain wins, else derive from TS_HOST
DOMAIN="${TF_VAR_tailnet_domain:-}"
if [ -z "$DOMAIN" ] && [ -n "${TS_HOST:-}" ]; then
  DOMAIN="${TS_HOST#*.}"
fi
if [ -z "$DOMAIN" ]; then
  echo "WARNING: can't determine tailnet domain — set TF_VAR_tailnet_domain or TS_HOST in .env" >&2
fi

# name:magicdns-host:local-ingress-host[:path]
apps=(
  "authentik:authentik:authentik.local"
  "gitlab:gitlab:gitlab.local"
  "minio (API):minio:minio.local"
  "minio (console):minio-console:minio-console.local"
  "n8n:n8n:"
  "sonarqube:sonarqube:sonarqube.local"
  "nextcloud:nextcloud:nextcloud.local"
  "argocd:argocd:argocd.local"
  "grafana:grafana:grafana.local"
  "litellm:litellm::/ui"
  "openwebui:openwebui:"
)

# ponytail: no -L — the SSO apps 302/307 to a login page (and litellm's 307
# Location is plain http, which the operator node doesn't serve); following it
# just burns the timeout. 2xx/3xx/401/403 all mean "app is up".
# TIMEOUT: a cold nextcloud / operator-proxy first response can be slow; default
# 20s, override with LIST_URLS_TIMEOUT=<seconds>.
TIMEOUT="${LIST_URLS_TIMEOUT:-20}"
check() {
  local code
  code=$(curl -sk -o /dev/null -m "$TIMEOUT" --connect-timeout 5 -w '%{http_code}' "$1" 2>/dev/null)
  code=${code:-000}
  case "$code" in
    2??|3??|401|403) echo "OK ($code)" ;;
    000)             echo "unreachable" ;;
    *)               echo "DOWN ($code)" ;;
  esac
}

# ponytail: the operator appends -1/-2 to the hostname when the bare name is
# still held by a stale device, so don't construct <app>.<domain> — read the
# name the operator actually assigned. One cluster-wide query, cached; falls
# back to the constructed name if kubectl / the ingress isn't there.
ts_hosts=""
if command -v kubectl >/dev/null 2>&1; then
  ts_jsonpath='{range .items[?(@.spec.ingressClassName=="tailscale")]}{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'
  ts_hosts=$(kubectl get ingress -A -o jsonpath="$ts_jsonpath" 2>/dev/null || true)
fi
ts_host_for() {
  local h
  h=$(printf '%s\n' "$ts_hosts" | awk -F'\t' -v n="ts-$1" '$1==n && $2!=""{print $2; exit}')
  [ -n "$h" ] && { echo "$h"; return; }
  echo "$1.${DOMAIN}"
}

printf "%-18s %-45s %-14s\n" "APP" "TAILSCALE (operator)" "STATUS"
for entry in "${apps[@]}"; do
  IFS=':' read -r name host ingress_host path <<< "$entry"
  ts_url="https://$(ts_host_for "$host")${path:-}"
  printf "%-18s %-45s %-14s\n" "$name" "$ts_url" "$(check "$ts_url")"
done

echo
echo "LAN fallback (need /etc/hosts entry + trust the homelab CA):"
for entry in "${apps[@]}"; do
  IFS=':' read -r name host ingress_host path <<< "$entry"
  [ -n "$ingress_host" ] && echo "  https://${ingress_host}  ($name)"
done
