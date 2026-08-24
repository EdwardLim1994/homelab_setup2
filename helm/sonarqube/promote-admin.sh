#!/bin/sh
# ponytail: no-op until ADMIN_EMAIL has logged in via SSO at least once
# (JIT-creates the account) — safe to re-run on every Tilt reload. Uses
# the default admin/admin credentials (never changed in this dev cluster,
# same assumption the rest of this repo makes about SonarQube's bootstrap).
set -e

# ponytail: runs on the Tilt host against the port-forward (localhost:9010),
# not inside the pod — the official sonarqube image has curl but no
# python3/jq to parse JSON with, the host running Tilt has both.
login=$(curl -sk -u admin:admin "http://localhost:9010/api/users/search?q=${ADMIN_EMAIL}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); u=[x for x in d['users'] if x.get('email')=='${ADMIN_EMAIL}']; print(u[0]['login'] if u else '')")

if [ -z "$login" ]; then
  echo "sonarqube admin skipped: no user yet for ${ADMIN_EMAIL} (log in via SSO first)"
  exit 0
fi

curl -sk -u admin:admin -X POST \
  "http://localhost:9010/api/user_groups/add_user?login=${login}&name=sonar-administrators"
echo "sonarqube admin ready: ${login}"
