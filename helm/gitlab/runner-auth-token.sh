#!/bin/sh
# ponytail: runs INSIDE the gitlab webservice pod (via `kubectl exec ... sh <`).
# Creates — or reuses — an instance runner and prints its glrt- authentication
# token. GitLab 18 removed runner registration tokens; the helm chart's bundled
# runner still reads a token from gitlab-gitlab-runner-secret, so this supplies
# the modern one. Idempotent on the runner description.
set -e
cd /srv/gitlab

DESC="homelab-k8s"

bundle exec rails runner "
  u = User.admins.active.first || User.find_by(username: 'root')
  raise 'no admin user yet — log in via SSO once' if u.nil?
  # GitLab 18 gates instance-runner creation behind admin mode.
  Gitlab::Auth::CurrentUserMode.bypass_session!(u.id)

  r = ::Ci::Runner.instance_type.find_by(description: '${DESC}')
  r&.destroy unless r.nil? || r.token.to_s.start_with?('glrt-')
  unless r&.token.to_s.start_with?('glrt-')
    res = ::Ci::Runners::CreateRunnerService.new(
      user: u,
      params: { runner_type: 'instance_type', description: '${DESC}', run_untagged: true, tag_list: [] }
    ).execute
    raise((res.errors || [res.message]).join(', ')) unless res.success?
    r = res.payload[:runner]
  end
  puts \"RUNNER_AUTH_TOKEN=#{r.token}\"
"
