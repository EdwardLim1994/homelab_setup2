# ponytail: official taigaio/taiga-back has no OIDC support. The only gap is
# one pip package (settings/local.py + settings/urls.py deliver the actual
# config as ConfigMap-mounted files, no baking needed — see templates/back.yaml).
# taiga-contrib-oidc-auth was never published to PyPI (GitHub-only, no
# setup.py at repo root either — installable subdir is back/) — needs `git`,
# which this image doesn't ship.
#
# Everything here installs --no-deps: the plugin's setup.py pins
# "django > 3, < 4" (stale since ~2021), and mozilla-django-oidc's own
# unpinned "Django" requirement resolves to whatever's newest on PyPI
# (5.2.x) — either one left unpinned uninstalls/reinstalls the exact
# Django 3.2.25 this taiga-back image is actually built and tested against,
# breaking it. mozilla-django-oidc's own real (non-Django) runtime deps
# (requests, cryptography) are already in the base image; josepy is the one
# genuinely missing piece, added explicitly.
#
# Built+pushed by terraform/internal/taiga.tf's null_resource, same pattern
# terraform/internal/omp-agent.tf uses for the omp image.
FROM taigaio/taiga-back:latest
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir --no-deps josepy mozilla-django-oidc six \
    "git+https://github.com/taigaio/taiga-contrib-oidc-auth.git#subdirectory=back"
