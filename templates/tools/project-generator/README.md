# project-generator

This library was generated with [Nx](https://nx.dev).

## Building

Run `nx build project-generator` to build the library.

## Running unit tests

Run `nx test project-generator` to execute the unit tests via [Vitest](https://vitest.dev/).

## Generators

### `nest-grpc`

```bash
nx g project-generator:nest-grpc orders
```

Scaffolds a fresh NestJS project with the real Nest CLI (`nest new`, falling back
to `npx @nestjs/cli` if `nest` isn't on PATH) into `apps/<name>`, then overlays a
gRPC microservice setup:

- `src/main.ts` bootstraps a `Transport.GRPC` microservice (`GRPC_URL` env, default `0.0.0.0:5000`)
- `proto/<name>.proto` sample service + `@GrpcMethod` handler in `app.controller.ts`
- adds `@nestjs/microservices`, `@grpc/grpc-js`, `@grpc/proto-loader` to the project's `package.json`
- `nest-cli.json` ships `proto/**/*.proto` into the build output
- registered with Nx as an application; `build` / `serve` / `test` delegate to the in-project npm scripts
- generates a per-service agent skill at `.opencode/skills/<name>-service/SKILL.md` (proto contract, how to add RPCs); `--skill=false` to skip
- copies bundled third-party skills (`nestjs-expert`, `typescript-pro`, `sql-pro`, `database-optimizer`, `debugging-wizard`, `test-master`) into `.opencode/skills/`, merging `skills-lock.json`; `--curatedSkills=false` to skip

To refresh the bundled skills, replace `src/nest-grpc/files/curated-skills/**`
and `curated-skills-lock.json` from the upstream skills repo — they are copied
verbatim (no templating).

### `nest-graphql`

```bash
nx g project-generator:nest-graphql catalog
```

Same scaffold flow as `nest-grpc` (real Nest CLI into `apps/<name>`), overlaid
with a code-first (Apollo) GraphQL setup:

- `app.module.ts` registers `GraphQLModule.forRoot` with `ApolloDriver`, `autoSchemaFile: src/schema.gql`, playground on
- `app.resolver.ts` — `@Resolver` with a `hello` `@Query`; REST `app.controller.ts` removed
- `main.ts` plain HTTP bootstrap (`PORT` env, GraphQL at `/graphql`)
- adds `@nestjs/graphql`, `@nestjs/apollo`, `@apollo/server`, `graphql`
- `src/schema.gql` (generated at runtime) added to the project's `.gitignore`
- registered with Nx as an application
- per-service skill at `.opencode/skills/<name>-service/`; `--skill=false` to skip
- curated skills (`nestjs-expert`, `typescript-pro`, `debugging-wizard`, `test-master` — no SQL ones) into `.opencode/skills/`, merging `skills-lock.json`; `--curatedSkills=false` to skip

### `nest-cron`

```bash
nx g project-generator:nest-cron billing-jobs
```

Same scaffold flow as `nest-grpc`, overlaid with `@nestjs/schedule`:

- `main.ts` — headless worker (`createApplicationContext`, no HTTP); scheduled jobs keep it alive
- `app.module.ts` — `ScheduleModule.forRoot()`, registers `TasksService`
- `tasks.service.ts` — sample `@Cron` / `@Interval` / `@Timeout` jobs + spec; scaffold's `app.controller`/`app.service` removed
- adds `@nestjs/schedule` (bundles `cron`)
- per-service skill + curated skills (`nestjs-expert`, `typescript-pro`, `sql-pro`, `database-optimizer`, `debugging-wizard`, `test-master`); `--skill=false` / `--curatedSkills=false` to skip

### `nest-rest`

```bash
nx g project-generator:nest-rest accounts-api
```

Stock `nest new` REST API into `apps/<name>` — **no overlay**, the scaffold is
left exactly as the Nest CLI produces it. Adds:

- per-service skill at `.opencode/skills/<name>-service/` (how to `nest g resource`, DTO/validation notes)
- curated skills (`nestjs-expert`, `typescript-pro`, `sql-pro`, `database-optimizer`, `debugging-wizard`, `test-master`)
- registered with Nx as an application

`--skill=false` / `--curatedSkills=false` to skip the skills.

### `server-integration-test`

```bash
nx g project-generator:server-integration-test orders-api
```

Generates an API-to-API integration test project under `apps/<name>` — Vitest +
native `fetch`, no mocks, run against live services:

- `src/config.ts` — service base URLs from env (`API_BASE_URL`, plus any downstream)
- `src/api-client.ts` — `createApiClient(baseUrl)` (`get`/`post`/`put`/`patch`/`delete`, JSON in/out)
- `tests/setup.ts` — pre-flight reachability check on every configured service
- `tests/<name>.spec.ts` — health + 404 examples, commented API-to-API example
- Nx target `test` runs `npx vitest run` (uncached; `fileParallelism: false`)
- bundled skill `test-master` → `.opencode/skills/`, merging `skills-lock.json`; `--curatedSkills=false` to skip

No `package.json` / install — `vitest` resolves from the workspace root.

### `web-integration-test`

```bash
nx g project-generator:web-integration-test storefront-web
```

Generates a [Playwright](https://playwright.dev) browser test project under
`apps/<name>` — **headless by default** (`use.headless: true`), Chromium only:

- `playwright.config.ts` — `BASE_URL` env, HTML + list/github reporters, trace on first retry, `webServer` block commented
- `tests/<name>.spec.ts` — home-page load + console-error examples
- `package.json` with `@playwright/test` (Playwright is not in the workspace root)
- `.env.example`, `.gitignore` (reports/results), `README.md`
- Nx target `test` runs `npx playwright test` (uncached)
- bundled skills `playwright-expert`, `test-master` → `.opencode/skills/`, merging `skills-lock.json`; `--curatedSkills=false` to skip

After generating: `cd apps/<name> && npm install && npx playwright install chromium`.

### `e2e-test`

```bash
nx g project-generator:e2e-test shop-e2e
```

Like `web-integration-test`, but for full user journeys against a running stack:

- `playwright.config.ts` — headless, `video: retain-on-failure`, `webServer` wired to `WEB_SERVER_CMD` (Playwright boots the stack when set, else assumes it's up)
- `tests/<name>.spec.ts` — a single journey skeleton to flesh out
- `package.json` (`@playwright/test`), `.env.example`, `.gitignore`, `README.md`
- Nx target `e2e` runs `npx playwright test` (uncached)
- bundled skills `playwright-expert`, `test-master` → `.opencode/skills/`, merging `skills-lock.json`; `--curatedSkills=false` to skip

Setup: `cd apps/<name> && npm install && npx playwright install chromium`.

### Notes

Deps are **not** installed (the Nest CLI runs with `--skip-install`); run your
package manager's install in `apps/<name>` afterwards. The Nest CLI is invoked as
`nest` when on PATH, otherwise `npx @nestjs/cli`.
