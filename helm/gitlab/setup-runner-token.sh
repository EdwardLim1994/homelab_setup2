#!/usr/bin/env bash
# ponytail: host-side glue — get a runner auth token out of the webservice pod
# (runner-auth-token.sh) and write it into the chart's runner secret, then
# bounce the runner so it picks it up. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

# ponytail: pass the root password through so runner-auth-token.sh can create
# the root admin if the chart never seeded one.
ROOT_PW=$(kubectl get secret -n gitlab gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 -d)

# ponytail: a fresh `helm upgrade` rolls gitlab-postgresql, which then does crash
# recovery for ~2-3 min on local-path storage ("the database system is starting
# up" / "Connection refused"). Retry the whole thing instead of failing the
# apply — 40 x 15s = 10 min ceiling.
TOKEN=""
for i in $(seq 1 40); do
  OUT=$(kubectl exec -i -n gitlab deploy/gitlab-webservice-default -c webservice -- \
    env GITLAB_ROOT_PASSWORD="$ROOT_PW" sh < runner-auth-token.sh 2>&1 || true)
  TOKEN=$(printf '%s' "$OUT" | grep -o 'RUNNER_AUTH_TOKEN=[^[:space:]]*' | cut -d= -f2 || true)
  [ -n "$TOKEN" ] && break
  echo "gitlab not ready yet (attempt $i/40): $(printf '%s' "$OUT" | grep -viE '^\s+from ' | tail -1)" >&2
  sleep 15
done

if [ -z "${TOKEN:-}" ]; then
  echo "could not obtain runner auth token from gitlab" >&2
  exit 1
fi

kubectl patch secret -n gitlab gitlab-gitlab-runner-secret --type merge \
  -p "{\"stringData\":{\"runner-token\":\"${TOKEN}\",\"runner-registration-token\":\"\"}}"

kubectl rollout restart -n gitlab deploy/gitlab-gitlab-runner
echo "runner auth token installed (glrt-…), runner restarting"
