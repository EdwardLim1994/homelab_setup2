{{/*
opencode.podSpec — container/volume spec shared by the always-on "opencode"
Deployment, the "opencode-slot-N" spawn pool, and the per-role pods. Args: a dict with
  .root           chart context
  .skillsRepo     per-instance git URL, "" = image skills only
  .workspaceClaim PVC name for /workspace, "" = ephemeral emptyDir
  .roleSkill      role name, "" = none. Mounts <release>-role-<name> ConfigMap
                  (that role's SKILL.md) into the opencode skill dir — no git.
ponytail: one definition so the slot pool and role pods can't drift from the real pod.
*/}}
{{- define "opencode.podSpec" -}}
{{- $root := .root -}}
{{- $repo := .skillsRepo -}}
{{- $role := .roleSkill | default "" -}}
{{- if $repo }}
initContainers:
  - name: fetch-skills
    image: alpine/git:latest
    args: ["clone", "--depth", "1", {{ $repo | quote }}, "/skills-src"]
    volumeMounts:
      - name: skills-src
        mountPath: /skills-src
{{- end }}
containers:
  - name: opencode
    image: {{ $root.Values.image }}
    {{- if $repo }}
    command: ["sh", "-c"]
    args:
      - |
        cp -a /skills-src/skills/. /root/.config/opencode/skills/ 2>/dev/null || true
        exec {{ concat $root.Values.command $root.Values.args | join " " }}
    {{- else }}
    command: {{ toYaml $root.Values.command | nindent 6 }}
    args: {{ toYaml $root.Values.args | nindent 6 }}
    {{- end }}
    ports:
      - containerPort: {{ $root.Values.port }}
    {{- with $root.Values.env }}
    env:
      {{- range $k, $v := . }}
      - name: {{ $k }}
        value: {{ $v | quote }}
      {{- end }}
    {{- end }}
    {{- if $root.Values.claudeAuth.secretName }}
    # ponytail: CLAUDE_CODE_OAUTH_TOKEN for pods running `claude` instead of
    # opencode. optional:true so a missing/empty Secret never blocks startup.
    envFrom:
      - secretRef:
          name: {{ $root.Values.claudeAuth.secretName }}
          optional: true
    {{- end }}
    volumeMounts:
      - name: workspace
        mountPath: /workspace
      {{- if $repo }}
      - name: skills-src
        mountPath: /skills-src
      {{- end }}
      {{- if $role }}
      - name: role-skill
        mountPath: /root/.config/opencode/skills/{{ $role }}
        readOnly: true
      {{- end }}
      {{- if $root.Values.dockerSocket.enabled }}
      - name: docker-sock
        mountPath: /var/run/docker.sock
      {{- end }}
    resources:
      {{- toYaml $root.Values.resources | nindent 6 }}
volumes:
  - name: workspace
    {{- if .workspaceClaim }}
    persistentVolumeClaim:
      claimName: {{ .workspaceClaim }}
    {{- else }}
    emptyDir: {}
    {{- end }}
  {{- if $repo }}
  - name: skills-src
    emptyDir: {}
  {{- end }}
  {{- if $role }}
  - name: role-skill
    configMap:
      name: {{ $root.Release.Name }}-role-{{ $role }}
  {{- end }}
  {{- if $root.Values.dockerSocket.enabled }}
  - name: docker-sock
    hostPath:
      path: {{ $root.Values.dockerSocket.hostPath }}
      type: Socket
  {{- end }}
{{- end -}}
