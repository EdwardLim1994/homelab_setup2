set -e
until wget -q -O /dev/null "$BAO_ADDR/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200"; do
  echo "waiting for openbao to be reachable..."
  sleep 2
done

# No kubectl/curl in this image — a single create-or-get call against the Kubernetes API is easy
# enough with plain busybox wget instead. Same approach the old services/vault chart (removed
# earlier) used for its own vault-init-job.yaml, adapted for OpenBao's identical init/unseal API.
KUBE_TOKEN_FILE=/var/run/secrets/kubernetes.io/serviceaccount/token
KUBE_CA_FILE=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
cat "$KUBE_CA_FILE" >> /etc/ssl/certs/ca-certificates.crt
AUTH_HEADER="Authorization: Bearer $(cat "$KUBE_TOKEN_FILE")"
KUBE_API="https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE"

# `-format=json` pretty-prints (space after the colon: `"initialized": true`), not the compact
# `"initialized":true` form — tolerate the optional space.
INITIALIZED=$(bao status -format=json | grep -o '"initialized": *[a-z]*' | cut -d: -f2 | tr -d ' ')

if [ "$INITIALIZED" != "true" ]; then
  echo "first boot — initializing openbao"
  # Flattened to one whitespace-free line (tr -d) — the unseal_keys_b64 array spans multiple
  # lines in the pretty-printed output otherwise, which breaks every later grep against this
  # same blob (both the write path here and the re-read path below).
  bao operator init -key-shares=5 -key-threshold=3 -format=json | tr -d ' \t\n' > /tmp/init.json

  if wget -q -O /dev/null --header="$AUTH_HEADER" "$KUBE_API/secrets/openbao-init" 2>/dev/null; then
    echo "openbao-init secret already exists but openbao reports uninitialized — refusing to overwrite, needs manual review"
    exit 1
  fi

  B64=$(base64 -w0 /tmp/init.json)
  printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"openbao-init","namespace":"%s"},"data":{"init.json":"%s"}}' \
    "$NAMESPACE" "$B64" > /tmp/secret-body.json
  wget -q -O - \
    --header="$AUTH_HEADER" \
    --header="Content-Type: application/json" \
    --post-file=/tmp/secret-body.json \
    "$KUBE_API/secrets" >/dev/null
else
  echo "already initialized — fetching stored unseal keys"
  wget -q -O - --header="$AUTH_HEADER" "$KUBE_API/secrets/openbao-init" \
    | grep -o '"init.json": *"[^"]*"' | cut -d'"' -f4 | base64 -d > /tmp/init.json
fi

SEALED=$(bao status -format=json | grep -o '"sealed": *[a-z]*' | cut -d: -f2 | tr -d ' ')
if [ "$SEALED" = "true" ]; then
  echo "unsealing"
  for i in 0 1 2; do
    KEY=$(grep -o '"unseal_keys_b64":\[[^]]*\]' /tmp/init.json | sed 's/.*\[//;s/\]//' | tr ',' '\n' | sed -n "$((i + 1))p" | tr -d '"')
    bao operator unseal "$KEY" >/dev/null
  done
fi

rm -f /tmp/init.json /tmp/secret-body.json
