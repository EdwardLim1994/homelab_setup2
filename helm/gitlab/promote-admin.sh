#!/bin/sh
# ponytail: no-op until ADMIN_EMAIL has logged in via SSO once (creates the
# GitLab user row) — safe to re-run on every Tilt reload regardless.
set -e
cd /srv/gitlab
bundle exec rails runner "
u = User.find_by(email: '${ADMIN_EMAIL}')
if u
  u.update!(admin: true) unless u.admin?
  puts \"gitlab admin ready: #{u.username}\"
else
  puts \"gitlab admin skipped: no user yet for ${ADMIN_EMAIL} (log in via SSO first)\"
end
"
