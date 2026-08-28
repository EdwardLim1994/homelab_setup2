# skill-generator

Nx generators that install **agent skills** into a workspace, under
`.opencode/skills/`. Each role generator installs:

- the role's own `SKILL.md` → `.opencode/skills/<role>/SKILL.md`
- its supporting skill pack (`files/curated-skills/**`) → `.opencode/skills/<skill>/`, merging `skills-lock.json`

Either part is skipped when the role doesn't have it, or via flags.

```bash
nx g skill-generator:qa-engineer
nx g skill-generator:tech-lead --curatedSkills=false     # role SKILL.md only
nx g skill-generator:data-engineer --roleSkill=false     # pack only
```

Skills are stored verbatim (no templating): `src/<role>/SKILL.md` and
`src/<role>/files/curated-skills/**` (+ `curated-skills-lock.json`). To refresh,
replace those files from upstream.

## Roles

| Role | own SKILL.md | pack |
|---|---|---|
| backend-developer | yes | — |
| data-engineer | yes | api-designer, database-optimizer, graphql-architect, microservices-architect |
| devops-engineer | yes | cloud-architect, devops-engineer, kubernetes-specialist, spec-miner, terraform-engineer |
| frontend-developer | yes | — |
| product-owner | yes | — |
| project-manager | yes | — |
| qa-engineer | yes | debugging-wizard, monitoring-expert, playwright-expert, spec-miner, test-master |
| react-developer | — | javascript-pro, react-expert, typescript-pro |
| react-native-developer | — | javascript-pro, react-native-expert, typescript-pro |
| release-manager | yes | — |
| security-engineer | yes | secure-code-guardian, security-reviewer, spec-miner |
| solution-architect | yes | api-designer, architecture-designer, graphql-architect, microservices-architect |
| tech-lead | yes | code-reviewer, database-optimizer, debugging-wizard, fine-tuning-expert, fullstack-guardian, secure-code-guardian, spec-miner, the-fool |
| technical-writer | — | code-documenter, spec-miner |
| uiux-designer | yes | brandkit, design-taste-frontend, full-output-enforcement, high-end-visual-design, image-to-code, imagegen-frontend-mobile, imagegen-frontend-web, industrial-brutalist-ui, minimalist-ui, redesign-existing-projects, stitch-design-taste |

## Testing

Run `nx test skill-generator`.
