# ponytail: debian slim + apt where it works; every tool that isn't in apt
# gets its upstream one-liner installer. Docker here is CLI + compose only,
# talking to the host socket the chart mounts — no in-pod daemon.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils gnupg python3 \
      build-essential pkg-config libssl-dev pandoc \
    && rm -rf /var/lib/apt/lists/*

# --- mc (MinIO client): plan_release/kickoff report hand-off via MinIO ---
# ponytail: the mc/minio-server/kes OSS projects are archived upstream —
# dl.min.io's client CDN now 410s every release, including old ones. Pull
# the final tagged binary straight from its GitHub release instead (still
# served); pinned since there will never be a newer one.
ARG MC_VERSION=RELEASE.2025-08-13T08-35-41Z
RUN curl -fsSL --retry 3 --retry-delay 2 \
      "https://github.com/minio/mc/releases/download/${MC_VERSION}/mc.linux-amd64.${MC_VERSION}" \
      -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

# --- docker CLI + buildx + compose plugin ---
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# --- node 20 (drives nx, openspec) ---
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# --- bun (also the omp install target) ---
# ponytail: BUN_INSTALL=/usr/local makes the installer drop the binary straight
# at /usr/local/bin/bun — no ~/.bun to move. (The old `mv /root/.bun/bin/bun`
# broke when the installer started honouring BUN_INSTALL for the binary path.)
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash \
    && bun --version

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

# --- npm-global CLIs: nx, openspec, codegraph, claude code ---
# ponytail: claude-code ships here too so a pod can run `claude` when the omp
# agent is not wanted (scripts/omp-shell.sh). Auth is the CLAUDE_CODE_OAUTH_TOKEN
# env the chart injects — no `claude login` in the pod.
RUN npm install -g \
      nx \
      @fission-ai/openspec \
      @colbymchenry/codegraph \
      @anthropic-ai/claude-code \
    && npm cache clean --force

# --- omp (oh-my-pi): the coding agent ---
# ponytail: bun global install -> /usr/local/bin/omp (BUN_INSTALL above). The
# omp.sh shell installer works too but picks its own dir; bun is deterministic
# and already here.
RUN bun install -g @oh-my-pi/pi-coding-agent \
    && omp --version

# codegraph wires itself into the agent configs. Best-effort at build; if it
# needs a live workspace, re-run `codegraph install` on first boot.
# ponytail: `|| true` so a non-fatal codegraph exit doesn't kill the build.
RUN codegraph install || true

# --- omp config: ~/.omp/agent ---
# ponytail: models.yml = provider wiring (host Ollama). config.yml = model
# choice + yolo approvals + quiet startup. RULES.md = always-apply sticky rule
# (the caveman/ponytail rulesets, appended below). Skills live in
# ~/.omp/agent/skills — omp also reads ~/.claude/skills, so the claude-code
# links below double as omp skills.
RUN mkdir -p /root/.omp/agent/skills /opt/src \
    && printf '%s\n' \
      'providers:' \
      '  ollama:' \
      '    baseUrl: http://host.docker.internal:11434' \
      '    api: openai-completions' \
      '    auth: none' \
      '    discovery:' \
      '      type: ollama' \
      > /root/.omp/agent/models.yml \
    && printf '%s\n' \
      'model: ollama/qwen3.8:27b' \
      'smol: ollama/qwen3:1.7b' \
      'tools:' \
      '  approvalMode: yolo' \
      'startup:' \
      '  quiet: true' \
      > /root/.omp/agent/config.yml

# --- caveman + ponytail rulesets: always-on via RULES.md ---
# ponytail: clone + copy rather than the vendors' per-agent installers, which
# assume an interactive Claude Code / Cursor setup. Skill dirs (any SKILL.md)
# get linked into omp's skill dir. For the always-on rulesets: ponytail ships a
# real AGENTS.md, but caveman's AGENTS.md is that repo's own dev file (internal
# routing notes) — its actual ruleset is skills/caveman/SKILL.md, so strip that
# file's YAML frontmatter and append the body instead.
RUN git clone --depth 1 https://github.com/juliusbrussee/caveman /opt/src/caveman \
    && git clone --depth 1 https://github.com/dietrichgebert/ponytail /opt/src/ponytail \
    && for f in $(find /opt/src -maxdepth 4 -name SKILL.md); do \
         d=$(dirname "$f"); ln -sfn "$d" "/root/.omp/agent/skills/$(basename "$d")"; \
       done \
    && { cat /opt/src/ponytail/AGENTS.md; echo; \
         awk 'p;/^---$/{c++;if(c==2)p=1}' /opt/src/caveman/skills/caveman/SKILL.md; echo; \
       } >> /root/.omp/agent/RULES.md; true

# --- claude code: skip first-run onboarding in a headless pod ---
# ponytail: without this, `claude` blocks the TUI on the theme picker /
# "trust this folder" dialog on first launch. Auth still comes from the
# CLAUDE_CODE_OAUTH_TOKEN env the chart injects.
RUN printf '%s\n' \
      '{' \
      '  "hasCompletedOnboarding": true,' \
      '  "theme": "dark",' \
      '  "autoUpdaterStatus": "disabled"' \
      '}' > /root/.claude.json

# --- SDLC role skills: baked into BOTH the omp and claude-code skill dirs ---
# ponytail: the per-role ConfigMap in roles.yaml ships only the top-level
# roles/<role>/SKILL.md; the curated sub-skill packs (with their references/)
# come from here. Every SKILL.md dir is linked into omp's dir AND
# /root/.claude/skills/ so `claude` discovers the same set. Duplicate sub-skill
# names across roles (spec-miner, database-optimizer, api-designer) are byte
# identical copies — ln -sfn just takes the last one.
COPY roles/ /opt/roles/
RUN mkdir -p /root/.claude/skills /root/.omp/agent/skills \
    && for f in $(find /opt/roles -maxdepth 3 -name SKILL.md); do \
         d=$(dirname "$f"); n=$(basename "$d"); \
         ln -sfn "$d" "/root/.omp/agent/skills/$n"; \
         ln -sfn "$d" "/root/.claude/skills/$n"; \
       done

# --- OpenAI-compatible shim: omp RPC session on :4096 ---
COPY adapter/pod-openai.py /opt/pod-openai.py

# --- publish-pdf.sh: plan_release's PDF-to-Nextcloud step ---
# ponytail: a ready-made script instead of asking the agent to author a
# 6-step raw-curl Kubernetes Job orchestration from prose at runtime — the
# prose version was fragile (first live test stalled mid-task). Agent just
# calls `publish-pdf.sh <project> <version> <revision> <markdown-file>`.
COPY scripts/publish-pdf.sh /usr/local/bin/publish-pdf.sh
RUN chmod +x /usr/local/bin/publish-pdf.sh

# --- render-mermaid.sh: plan_release's Mermaid-diagram-to-PNG step ---
# Wakes the scale-to-zero mermaid-render microservice (helm/mermaid-render),
# renders one diagram, scales it back down. See the script's own comments.
COPY scripts/render-mermaid.sh /usr/local/bin/render-mermaid.sh
RUN chmod +x /usr/local/bin/render-mermaid.sh

WORKDIR /workspace
EXPOSE 4096
