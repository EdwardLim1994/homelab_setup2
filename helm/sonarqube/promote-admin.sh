#!/bin/sh
# ponytail: no-op until ADMIN_EMAIL has logged in via SSO at least once
# (JIT-creates the account) — safe to re-run on every reload. Uses the
# default admin/admin credentials (never changed in this dev cluster).
#
# ponytail: runs INSIDE the sonarqube pod (kubectl exec -i ... sh <) against
# localhost:9000 — the image has curl + sed, so no host port-forward race and
# no dependency on a host python3/jq (Windows/Git-Bash python3 is the Store
# shim, which exits 1 non-interactively and killed the old host version).
set -e

resp=$(curl -sf -u admin:admin "http://localhost:9000/api/users/search?q=${ADMIN_EMAIL}" || true)

case "$resp" in
  "" | *'"total":0'*)
    echo "sonarqube admin skipped: sonarqube not ready, or no user yet for ${ADMIN_EMAIL} (log in via SSO first)"
    exit 0
    ;;
esac

# ponytail: relies on "login" being the first key of the first user object
# (SonarQube's field order). Fine for a dev cluster.
login=$(printf '%s' "$resp" | sed -n 's/.*"users":\[[[:space:]]*{[[:space:]]*"login":"\([^"]*\)".*/\1/p')

if [ -z "$login" ]; then
  echo "sonarqube admin: user search matched but could not parse a login from: $resp" >&2
  exit 1
fi

curl -sk -u admin:admin -X POST \
  "http://localhost:9000/api/user_groups/add_user?login=${login}&name=sonar-administrators"
echo "sonarqube admin ready: ${login}"
