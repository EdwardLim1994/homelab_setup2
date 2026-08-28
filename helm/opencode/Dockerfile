# ponytail: debian slim + apt where it works; every tool that isn't in apt
# gets its upstream one-liner installer. Docker here is CLI + compose only,
# talking to the host socket the chart mounts — no in-pod daemon.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils gnupg \
      build-essential pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# --- docker CLI + buildx + compose plugin ---
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# --- node 20 (drives nx, openspec, opencode) ---
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# --- bun ---
RUN curl -fsSL https://bun.sh/install | bash \
    && mv /root/.bun/bin/bun /usr/local/bin/bun

# --- rust (system-wide) ---
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --default-toolchain stable

# --- glab (GitLab CLI) ---
# ponytail: pinned; bump GLAB_VERSION when you need a newer one.
ARG GLAB_VERSION=1.53.0
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${ARCH}.tar.gz" \
       -o /tmp/glab.tgz \
    && tar -C /usr/local -xzf /tmp/glab.tgz bin/glab \
    && rm /tmp/glab.tgz

# --- npm-global CLIs: nx, openspec, opencode, codegraph ---
RUN npm install -g \
      nx \
      @fission-ai/openspec \
      opencode-ai \
      @colbymchenry/codegraph \
    && npm cache clean --force

# codegraph wires itself into the agent configs. Best-effort at build; if it
# needs a live workspace, re-run `codegraph install` on first boot.
# ponytail: `|| true` so a non-fatal codegraph exit doesn't kill the build.
RUN codegraph install || true

# --- opencode plugins, enabled by default ---
# ponytail: opencode resolves these from npm on first launch, so the pod's
# first wake needs egress to the npm registry. Bake a `opencode run` warm-up
# step here if the pod must run fully offline.
RUN mkdir -p /root/.config/opencode /root/.config/opencode/skill /opt/src \
    && printf '%s\n' \
      '{' \
      '  "$schema": "https://opencode.ai/config.json",' \
      '  "plugin": [' \
      '    "@dietrichgebert/ponytail",' \
      '    "openslimedit@latest"' \
      '  ]' \
      '}' > /root/.config/opencode/opencode.json

# --- caveman + ponytail rulesets: always-on via global AGENTS.md ---
# ponytail: clone + copy rather than the vendors' per-agent installers, which
# assume an interactive Claude Code / Cursor setup. Skill dirs (any SKILL.md)
# get linked into opencode's skill dir; the AGENTS.md rulesets are concatenated
# so both are injected every turn.
RUN git clone --depth 1 https://github.com/juliusbrussee/caveman /opt/src/caveman \
    && git clone --depth 1 https://github.com/dietrichgebert/ponytail /opt/src/ponytail \
    && find /opt/src -maxdepth 4 -name SKILL.md -print0 \
       | while IFS= read -r -d '' f; do \
           d=$(dirname "$f"); ln -sfn "$d" "/root/.config/opencode/skill/$(basename "$d")"; \
         done \
    && for f in /opt/src/ponytail/AGENTS.md /opt/src/caveman/AGENTS.md; do \
         [ -f "$f" ] && { cat "$f"; echo; } >> /root/.config/opencode/AGENTS.md; \
       done; true

WORKDIR /workspace
EXPOSE 4096
