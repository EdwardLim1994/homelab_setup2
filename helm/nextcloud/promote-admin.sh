#!/bin/bash
# ponytail: no-op until ADMIN_EMAIL has logged in via SSO once (Social Login
# JIT-creates the account) — safe to run on every Tilt/terraform reload.
# Finds the Nextcloud user whose email matches ADMIN_EMAIL and adds them to the
# built-in `admin` group. Social Login usernames are opaque (custom_oidc-<sub>),
# so match on email, not uid.
set -e
OCC="runuser -u www-data -- php /var/www/html/occ"
uid=$($OCC user:list --info --output=json | php -r '
  $j = json_decode(stream_get_contents(STDIN), true) ?: [];
  foreach ($j as $u => $i) {
    if (($i["email"] ?? "") === getenv("ADMIN_EMAIL")) { echo $u; exit; }
  }')
if [ -n "$uid" ]; then
  $OCC group:adduser admin "$uid"
  echo "nextcloud admin ready: $uid"
else
  echo "nextcloud admin skipped: no user yet for ${ADMIN_EMAIL} (log in via SSO first)"
fi
