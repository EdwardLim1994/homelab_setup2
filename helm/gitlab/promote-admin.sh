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

# ponytail: GitLab creates the internal 'GitLab Web IDE' OAuth app once, from
# whatever external URL config existed at creation, and never re-syncs it. A
# host/port change (or an app created before the host was fixed) leaves its
# redirect_uri pointing at the wrong origin -> 'callback URL do not match'.
# Realign it with the current config on every reload; cheap, idempotent.
app = Doorkeeper::Application.find_by(name: 'GitLab Web IDE')
want = \"#{Gitlab.config.gitlab.url}/-/ide/oauth_redirect\"
if app && app.redirect_uri.to_s.strip != want
  app.update!(redirect_uri: want)
  puts \"gitlab web ide oauth redirect fixed: #{want}\"
end

# ponytail: Web IDE VS Code extension marketplace. On 17.5 it is behind the
# 'web_ide_extensions_marketplace' feature flag (GA in 17.11) plus an instance
# setting, and each user still opts in under Preferences > Integrations.
# Ceiling: this bulk-opts-in existing users only; users created later must
# still flip their own toggle (or bump GitLab past 17.11 where the flag and
# some of the friction is gone).
Feature.enable(:web_ide_extensions_marketplace) unless Feature.enabled?(:web_ide_extensions_marketplace)
# opt-in is per-user (user_preferences.extensions_marketplace_opt_in_status:
# 0 unset / 1 enabled / 2 disabled). No instance-wide default in 17.5, so flip
# every existing preference row to enabled.
n = UserPreference.where.not(extensions_marketplace_opt_in_status: 1).update_all(extensions_marketplace_opt_in_status: 1)
puts \"gitlab web ide marketplace: flag on, opt-in enabled for #{n} user pref row(s)\"
"
