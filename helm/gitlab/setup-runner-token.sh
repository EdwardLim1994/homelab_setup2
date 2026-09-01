#!/usr/bin/env bash
# ponytail: host-side glue — get a runner auth token out of the webservice pod
# (runner-auth-token.sh) and write it into the chart's runner secret, then
# bounce the runner so it picks it up. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

TOKEN=$(kubectl exec -i -n gitlab deploy/gitlab-webservice-default -c webservice -- sh < runner-auth-token.sh \
  | grep -o 'RUNNER_AUTH_TOKEN=[^[:space:]]*' | cut -d= -f2 || true)

if [ -z "${TOKEN:-}" ]; then
  echo "could not obtain runner auth token from gitlab" >&2
  exit 1
fi

kubectl patch secret -n gitlab gitlab-gitlab-runner-secret --type merge \
  -p "{\"stringData\":{\"runner-token\":\"${TOKEN}\",\"runner-registration-token\":\"\"}}"

kubectl rollout restart -n gitlab deploy/gitlab-gitlab-runner
echo "runner auth token installed (glrt-…), runner restarting"
