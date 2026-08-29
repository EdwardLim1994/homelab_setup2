set -e
until bao status >/dev/null 2>&1; do
  echo "waiting for openbao..."
  sleep 2
done

if [ -z "$BAO_TOKEN" ]; then
  # Non-dev: no fixed dev root token exists — read the real one from the openbao-init Secret
  # openbao-init-job.yaml's own first-boot branch wrote (see that script's own comment for why
  # this is a raw wget against the K8s API, not kubectl).
  KUBE_TOKEN_FILE=/var/run/secrets/kubernetes.io/serviceaccount/token
  KUBE_CA_FILE=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  cat "$KUBE_CA_FILE" >> /etc/ssl/certs/ca-certificates.crt
  AUTH_HEADER="Authorization: Bearer $(cat "$KUBE_TOKEN_FILE")"
  KUBE_API="https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE"
  export BAO_TOKEN=$(wget -q -O - --header="$AUTH_HEADER" "$KUBE_API/secrets/openbao-init" \
    | grep -o '"init.json": *"[^"]*"' | cut -d'"' -f4 | base64 -d \
    | grep -o '"root_token":"[^"]*"' | cut -d'"' -f4)
fi

bao auth enable kubernetes 2>/dev/null || true
# No explicit token_reviewer_jwt — omitting it makes the kubernetes auth method fall back to
# this pod's own (the openbao server's) already-mounted, kubelet-refreshed ServiceAccount token,
# read fresh on every TokenReview call rather than a one-shot snapshot. The old services/vault
# chart (removed earlier) needed a hand-rolled long-lived-token Secret workaround here because a
# *separate, short-lived provisioning Job's own pod* went away after running once, staling out
# its token; this chart's server pod is long-running (a StatefulSet), so that whole problem class
# doesn't apply — the default in-cluster auto-detection is correct and simpler.
bao write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"

bao secrets enable -path=secret kv-v2 2>/dev/null || true

# Mount accessor is per-install (regenerated every fresh init), not a fixed string — extract it
# fresh every run rather than hardcoding. `-format=json`'s pretty-printed output has a space after
# each colon (same tolerance every other provisioning job in this repo's history needed for the
# apiserver/CLI's own JSON output — see the old services/vault/helm/templates/*.yaml, removed
# earlier, for the identical fix applied to a different JSON blob).
ACCESSOR=$(bao auth list -format=json | grep -A5 '"kubernetes/"' | grep -o '"accessor": *"[^"]*"' | head -1 | cut -d'"' -f4)

# Templated policy, not one static path — {{identity.entity.aliases.<accessor>.metadata.service_account_name}}
# is OpenBao's own identity-templating syntax (resolved server-side at request time against the
# *authenticating* pod's own ServiceAccount name), so this single policy scopes every current and
# future apps/servers/* workload to only its own secret/data/servers/<its-own-name>/* path — no
# per-server policy/role provisioning needed. ACCESSOR is substituted via sed (a shell variable,
# known only at runtime), not Helm templating — see this chart's own values.yaml header comment
# for why this whole script lives in files/, loaded via .Files.Get, instead of being inlined into
# the Job's own template (Helm's Go-templating and this HCL's own {{...}} syntax use the same
# delimiter).
cat > /tmp/policy.hcl <<'EOF'
path "secret/data/servers/{{identity.entity.aliases.ACCESSOR_PLACEHOLDER.metadata.service_account_name}}/*" {
  capabilities = ["read", "create", "update"]
}
path "secret/metadata/servers/{{identity.entity.aliases.ACCESSOR_PLACEHOLDER.metadata.service_account_name}}/*" {
  capabilities = ["list"]
}
EOF
sed -i "s/ACCESSOR_PLACEHOLDER/$ACCESSOR/g" /tmp/policy.hcl
bao policy write server-app-secrets-policy /tmp/policy.hcl

# bound_service_account_names="*" + bound_service_account_namespaces="server-apps" (not a fixed
# list) — apps/servers/* all share the "server-apps" namespace (see apps/terraform/main.tf), and
# every server gets its own uniquely-named ServiceAccount (see turbo/generators's secrets
# extension) for the templated policy above to scope by, so there's no fixed list to maintain
# here as new servers get scaffolded.
bao write auth/kubernetes/role/server-app-secrets \
  bound_service_account_names="*" \
  bound_service_account_namespaces="server-apps" \
  policies="server-app-secrets-policy" \
  ttl=1h
