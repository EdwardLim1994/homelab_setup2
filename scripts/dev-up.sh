#!/usr/bin/env bash
# ponytail: `tilt up` on its own doesn't read .env — every time someone runs
# it directly, GITHUB_OAUTH_CLIENT_ID/SECRET (and everything else in .env)
# silently fall back to dev placeholders, breaking GitHub login until
# someone notices and hotfixes it by hand. This wrapper is the one thing to
# remember instead of the export incantation.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  source .env
  set +a
else
  echo "Warning: no .env found (copy .env.example to .env for real secrets like GitHub OAuth)." >&2
fi

exec tilt up --host 0.0.0.0 "$@"
