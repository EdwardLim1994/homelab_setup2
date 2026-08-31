#!/bin/sh
# ponytail: no-op until ADMIN_EMAIL has logged in via SSO at least once
# (JIT-creates the account) — safe to re-run on every Tilt reload. Uses
# the default admin/admin credentials (never changed in this dev cluster,
# same assumption the rest of this repo makes about SonarQube's bootstrap).
set -e

# ponytail: runs on the Tilt host against the port-forward (localhost:9010),
# not inside the pod (sonarqube image has curl, no jq/python). Parse with sed
# instead of depending on a host python3 — on Windows/Git-Bash that resolves
# to the Store shim, which exits 1 non-interactively and killed this script.
resp=$(curl -sk -u admin:admin "http://localhost:9010/api/users/search?q=${ADMIN_EMAIL}")

case "$resp" in
  *'"total":0'*)
    echo "sonarqube admin skipped: no user yet for ${ADMIN_EMAIL} (log in via SSO first)"
    exit 0
    ;;
esac

# ponytail: relies on "login" being the first key of the first user object
# (SonarQube's field order). Fine for a dev cluster; switch to jq-in-pod if
# that order ever changes.
login=$(printf '%s' "$resp" | sed -n 's/.*"users":\[[[:space:]]*{[[:space:]]*"login":"\([^"]*\)".*/\1/p')

if [ -z "$login" ]; then
  echo "sonarqube admin: user search matched but could not parse a login from: $resp" >&2
  exit 1
fi

curl -sk -u admin:admin -X POST \
  "http://localhost:9010/api/user_groups/add_user?login=${login}&name=sonar-administrators"
echo "sonarqube admin ready: ${login}"
