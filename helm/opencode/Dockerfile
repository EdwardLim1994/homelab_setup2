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
RUN mkdir -p /root/.config/opencode /root/.config/opencode/skills /opt/src \
    && printf '%s\n' \
      '{' \
      '  "$schema": "https://opencode.ai/config.json",' \
      '  "plugin": [' \
      '    "@dietrichgebert/ponytail",' \
      '    "openslimedit@latest"' \
      '  ],' \
      '  "model": "ollama/qwen3:1.7b",' \
      '  "small_model": "ollama/qwen3:1.7b",' \
      '  "permission": { "*": "allow" },' \
      '  "provider": {' \
      '    "ollama": {' \
      '      "npm": "@ai-sdk/openai-compatible",' \
      '      "name": "Ollama (host)",' \
      '      "options": { "baseURL": "http://host.k3d.internal:11434/v1" },' \
      '      "models": {' \
      '        "qwen3:1.7b": { "name": "qwen3:1.7b" },' \
      '        "qwen3-coder-next": { "name": "qwen3-coder-next" }' \
      '      }' \
      '    }' \
      '  }' \
      '}' > /root/.config/opencode/opencode.json

# --- caveman + ponytail rulesets: always-on via global AGENTS.md ---
# ponytail: clone + copy rather than the vendors' per-agent installers, which
# assume an interactive Claude Code / Cursor setup. Skill dirs (any SKILL.md)
# get linked into opencode's skill dir. For the always-on rulesets: ponytail
# ships a real AGENTS.md, but caveman's AGENTS.md is that repo's own dev file
# (internal routing notes) — its actual ruleset is skills/caveman/SKILL.md, so
# strip that file's YAML frontmatter and append the body instead.
# ponytail: unquoted find in a for-loop word-splits on whitespace, fine here
# because every skill dir name is one token; switch to -exec if that changes.
RUN git clone --depth 1 https://github.com/juliusbrussee/caveman /opt/src/caveman \
    && git clone --depth 1 https://github.com/dietrichgebert/ponytail /opt/src/ponytail \
    && for f in $(find /opt/src -maxdepth 4 -name SKILL.md); do \
         d=$(dirname "$f"); ln -sfn "$d" "/root/.config/opencode/skills/$(basename "$d")"; \
       done \
    && { cat /opt/src/ponytail/AGENTS.md; echo; \
         awk 'p;/^---$/{c++;if(c==2)p=1}' /opt/src/caveman/skills/caveman/SKILL.md; echo; \
       } >> /root/.config/opencode/AGENTS.md; true

WORKDIR /workspace
EXPOSE 4096
