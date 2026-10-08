---
name: java
description: Nx monorepo (via the Gradle plugin) + Spring Boot backend + React frontend + JUnit/Vitest testing conventions for this repo's generated projects when their stack (declared in CLAUDE.md / openspec/architecture.md) is Java. Use to get the exact module layout, build, and test-runner commands for a Java-backend project. For anything else — a different stack's build/test tooling, or deep Spring/React API patterns — this skill doesn't apply.
license: MIT
metadata:
  domain: language
  triggers: Java, Spring Boot, Gradle, Nx, JUnit, React, Vitest, monorepo
  role: specialist
  scope: implementation
  related-skills: typescript
---

# Java Stack (Nx + Spring Boot + React, Gradle + JUnit/Vitest)

Only load this when the project's declared stack is Java (check
`CLAUDE.md` or `openspec/architecture.md` first). The frontend in this
stack is still React/TypeScript (see the `typescript` skill's Frontend and
Vitest sections, which apply here unchanged) — only the backend differs
from the TypeScript stack: Spring Boot instead of NestJS, Gradle instead of
bun, JUnit instead of Vitest.

## Package manager: Gradle (backend), bun (frontend)

Backend modules use Gradle (`./gradlew`), never Maven — this repo
standardizes on one build tool for all Java code. Frontend stays on bun,
same as the `typescript` skill (`bun install --frozen-lockfile`,
`bunx nx ...`).

## Monorepo: Nx (via the Gradle plugin)

- Layout: `apps/backend/{service}/`, `apps/frontend/{app}/` — same
  convention regardless of backend language.
- Nx discovers Gradle modules through `@nx/gradle` (add it once with
  `nx g @nx/gradle:init`) — it infers an nx project from every
  `build.gradle`/`build.gradle.kts` under `apps/backend/*`, no separate
  app-generator command like `@nx/nest:app`. Scaffold the Spring Boot
  module itself via Spring Initializr (start.spring.io, or
  `gradle init --type java-application`) directly into
  `apps/backend/{service}/`, then let the Gradle plugin pick it up.
- Scaffold the frontend the same way the TypeScript stack does:
  `nx g @nx/react:app {app} --directory=apps/frontend/{app} --unitTestRunner=vitest`.
- **Before every commit**: `nx affected -t test,lint,build --base=main` —
  never run repo-wide, same rule as the TypeScript stack.

## Backend: Spring Boot

Standard Spring Boot module layout (`@RestController`, `@Service`,
`@Repository`, constructor-based dependency injection) — same
controller → service → repository separation backend-developer/SKILL.md
already requires regardless of stack. Build the shippable artifact with
`./gradlew bootJar` (executable fat JAR). Dockerfile stays multi-stage: the
final stage `COPY`s just that JAR and runs `java -jar {service}.jar` — no
Gradle/JDK build tooling in the final image, same shape as the TypeScript
stack's compiled-binary final stage, just a JAR instead of a bun-compiled
binary.

## Frontend: React

Identical to the TypeScript stack — see that skill's "Frontend: React"
section, nothing Java-specific here.

## Unit tests: JUnit (backend), Vitest (frontend)

- Backend: JUnit 5 — `./gradlew test`, or via Nx once the Gradle plugin's
  inferred `test` target exists: `nx test {service}`. Test files:
  `src/test/java/.../{Thing}Test.java`.
- Frontend: Vitest, identical to the TypeScript stack — `nx test {app}`,
  `*.spec.tsx`, `vi.fn()`/`vi.mock()`.
- Run only what changed, across both: `nx affected -t test --base=main`.

## Build/compile checking

`nx affected -t build --base=main` runs `./gradlew build` for backend
modules (compiles + runs JUnit) and the Vite/TS build for frontend. There's
no separate "typecheck" target for Java the way `tsc --noEmit` covers
TypeScript — Gradle's `compileJava` task is the equivalent check, already
included in `build`.
