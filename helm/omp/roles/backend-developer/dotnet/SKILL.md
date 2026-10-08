---
name: dotnet
description: Bazel monorepo + ASP.NET Core backend + Blazor frontend + dotnet test (xUnit) conventions for this repo's generated projects when their stack (declared in CLAUDE.md / openspec/architecture.md) is .NET. Use to get the exact module layout, build, and test-runner commands for a .NET project. For anything else — a different stack's build/test tooling — this skill doesn't apply.
license: MIT
metadata:
  domain: language
  triggers: dotnet, .NET, C#, ASP.NET Core, Blazor, Bazel, NuGet, xUnit
  role: specialist
  scope: implementation
---

# .NET Stack (Bazel + ASP.NET Core + Blazor, NuGet + xUnit)

Only load this when the project's declared stack is .NET (check
`CLAUDE.md` or `openspec/architecture.md` first). Unlike the TypeScript/
Java stacks, **everything here is .NET** — backend, frontend, and tests —
there's no bun/Node anywhere and the monorepo tool is Bazel, not Nx.

## Package manager: NuGet

Every `.csproj` declares its dependencies via `<PackageReference>`;
`dotnet restore` resolves them (Bazel's `rules_dotnet` invokes this
itself as part of a build — don't run it by hand except for local
IDE/tooling support). Never check in a `packages/` directory.

## Monorepo: Bazel

- Layout: `apps/backend/{service}/`, `apps/frontend/{app}/` — same
  directory convention this repo uses for every other stack, just built
  by Bazel instead of Nx.
- Each project needs a `BUILD.bazel` file using `rules_dotnet`
  (`@rules_dotnet//dotnet:defs.bzl`) — `csharp_binary`/`csharp_library`
  for the backend, `csharp_library` + whatever Blazor's Bazel rules
  expose for the frontend. Root `MODULE.bazel` pulls in `rules_dotnet`.
- Build one target: `bazel build //apps/backend/{service}/...`
- Test one target: `bazel test //apps/backend/{service}/...`
- **Before every commit**: scope to what changed, don't run `bazel test
  //...` repo-wide. Bazel has no built-in `nx affected` equivalent —
  use `bazel-diff` (computes the set of impacted targets between two
  commits) if it's wired into this repo, or `bazel query
  'rdeps(//..., set({changed BUILD-owning packages}))'` as a manual
  fallback.

## Backend: ASP.NET Core

Standard ASP.NET Core Web API — controllers/minimal-API endpoints,
services via constructor-injected DI, same controller → service →
repository separation backend-developer/SKILL.md requires regardless of
stack. Ship it as a self-contained single-file executable, not a
`dotnet run`-dependent image: `dotnet publish -r linux-x64
--self-contained -p:PublishSingleFile=true -o out`. Dockerfile stays
multi-stage: build stage runs the Bazel build + that publish step, final
stage `COPY`s just the resulting binary and runs it directly — no .NET
SDK, no NuGet cache, in the final image (same shape as the TypeScript
stack's compiled-binary final stage).

## Frontend: Blazor (WebAssembly)

Blazor WebAssembly, not Blazor Server — it compiles to static
wasm/JS/HTML assets, same static-file deployment shape as the React
frontend in the other stacks: build stage publishes it, final stage
serves the output from a static web server (e.g. nginx). If a project
genuinely needs Blazor Server instead (server-rendered, persistent
SignalR connection), it ships as a long-running process like the
backend above, not static assets — note that explicitly in
`openspec/architecture.md` if chosen, since it changes the deployment
shape.

## Testing: dotnet test (xUnit)

- Default template: xUnit (`dotnet new xunit`) — use it unless the
  project already has NUnit/MSTest tests to stay consistent with.
- Run via Bazel: `bazel test //apps/backend/{service}/...` (same for
  frontend component tests, if any).
- Test files: `{Thing}Tests.cs`, one test project per app
  (`apps/backend/{service}.Tests/`), referencing the app's project.
- Mocking: `Moq` or `NSubstitute` — pick whichever this project's
  `openspec/architecture.md` names, don't mix both in one project.

## Build/compile checking

`bazel build //...` (scoped per the affected-targets note above) is the
.NET equivalent of a typecheck step — C# is compiled, so a successful
build already proves type correctness; there's no separate `tsc
--noEmit`-style check to run.
