---
name: typescript
description: Nx monorepo, NestJS backend, React frontend, and Vitest unit-test conventions for this repo's generated projects when their stack (declared in CLAUDE.md / openspec/architecture.md) is TypeScript. Use to get the exact scaffolding generator, affected-checks, and test-runner commands for a TypeScript project. For anything else — a different stack's build/test tooling, or deep NestJS/React API patterns — this skill doesn't apply; use that ecosystem's own equivalent, or the nestjs-expert/typescript-pro skills for framework-level patterns.
license: MIT
metadata:
  domain: language
  triggers: TypeScript, Nx, NestJS, React, Vitest, monorepo, nx affected, nx test
  role: specialist
  scope: implementation
  related-skills: nestjs-expert, typescript-pro
---

# TypeScript Stack (Nx + NestJS + React + Vitest)

Only load this when the project's declared stack is TypeScript (check
`CLAUDE.md` or `openspec/architecture.md` first). A different stack uses a
different monorepo tool, framework, and test runner — this skill's commands
don't transfer.

## Package manager: bun

Use `bun`, not `npm`/`npx`/`yarn`, for every install and script-run step —
`bun install --frozen-lockfile`, `bunx nx ...`, `bun publish`. Never `npm
ci`, `npx nx`, or `npm publish`.

## Monorepo: Nx

- Layout: `apps/backend/{service}/`, `apps/frontend/{app}/`
- Scaffold a backend service: `nx g @nx/nest:app {service} --directory=apps/backend/{service} --unitTestRunner=vitest`
- Scaffold a frontend app: `nx g @nx/react:app {app} --directory=apps/frontend/{app} --unitTestRunner=vitest`
- Nx defaults to Jest if `--unitTestRunner=vitest` is omitted — always pass it explicitly, this repo's convention is Vitest everywhere.
- Resolve an existing service's root: `nx show project {service} --json | jq -r .root`
- **Before every commit**: `nx affected -t test,lint,typecheck --base=main`
  — never run repo-wide (`nx test`/`nx lint` without `affected`), this
  monorepo is too large for that.

## Backend: NestJS

Nx-level wiring only — module/controller/service/DI patterns, guards, and
auth live in the `nestjs-expert` skill, load that too when implementing.

Dockerfile stays multi-stage, but the final stage ships a compiled binary,
not a `node_modules` runtime: build stage runs `nx build {service}` then
`bun build --compile ./dist/main.js --outfile {service}`; the final stage
`COPY`s only that binary and runs it directly — no `bun install
--production`, no `node_modules`, no bun/node runtime in the final image.

## Frontend: React

Standard function components + hooks. Scaffold via `nx g @nx/react:app`
above. No house state-management opinion here — follow whatever `CLAUDE.md`
names for this project.

## Unit tests: Vitest

Nx projects here use the `@nx/vite` executor for the `test` target, not
Jest or `bun test`.

- Run one project: `nx test {project}`
- Run one file: `nx test {project} --testFile={path}`
- Run only what changed: `nx affected -t test --base=main`
- Test files: `*.spec.ts` / `*.spec.tsx`, colocated with the source file
- Mocking: `vi.fn()`, `vi.mock()`, `vi.spyOn()` — not `jest.*`

## Type checking

`nx affected -t typecheck --base=main` wraps `tsc --noEmit` per project. For
advanced type-system work (generics, branded types, tRPC), load
`typescript-pro` instead — this skill only covers the Nx-level command.
