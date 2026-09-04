#!/bin/sh
# ponytail: runs INSIDE the gitlab webservice pod (via `kubectl exec ... sh <`).
# Creates — or reuses — an instance runner and prints its glrt- authentication
# token. GitLab 18 removed runner registration tokens; the helm chart's bundled
# runner still reads a token from gitlab-gitlab-runner-secret, so this supplies
# the modern one. Idempotent on the runner description.
#
# ponytail: also ensures the `root` admin exists — the chart's migrations job
# only seeds it on a truly empty schema, and a Postgres PVC that outlived a
# cluster recreate can leave a schema with no users. Needs GITLAB_ROOT_PASSWORD
# in the environment (setup-runner-token.sh passes it from the secret).
set -e
cd /srv/gitlab

DESC="homelab-k8s"

bundle exec rails runner "
  u = User.find_by(username: 'root')
  if u.nil?
    pw = ENV['GITLAB_ROOT_PASSWORD'].to_s
    raise 'no root user and GITLAB_ROOT_PASSWORD not set' if pw.empty?
    org = Organizations::Organization.first
    u = User.new(username: 'root', name: 'Administrator', email: 'admin@example.com', admin: true)
    u.assign_personal_namespace(org)
    u.password = pw
    u.password_confirmation = pw
    u.skip_confirmation!
    # validate:false — bypass password-strength / namespace-presence checks;
    # the operator picked this password in .env on purpose.
    u.save!(validate: false)
  end
  u.update_column(:admin, true) unless u.admin?
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
