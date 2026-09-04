# CLAUDE.md

## Project Overview

SnapSort is a polyglot monorepo image classification app. It demonstrates dev container composition with Azure emulation for a lunch-and-learn.

## Directory Conventions

- `apps/` — deployable code units (`web-app`, `mobile`, `web-api`, `worker`)
- `libs/` — shared libraries (data layer with EF Core models, DbContext, migrations)
- `tests/` — `unit/` (fast, no infrastructure) and `integration/` (API via `WebApplicationFactory`)
- `scripts/` — helper scripts; the worktree ones (`new-worktree.sh`, `remove-worktree.sh`, `migrate-to-bare-layout.sh`) run on the **host**, not in the container
- `docs/` — longer-form docs, e.g. `devcontainer-worktrees.md`
- `.devcontainer/` — all dev container configuration (Dockerfile, docker-compose.yml, devcontainer.json, init.sh)
- Solution file `SnapSort.slnx` lives at repo root and references all .csproj files
- `.config/dotnet-tools.json` pins `dotnet-ef`; keep its version in step with the EF Core packages

## Tech Stack

- **Web App**: React 19 + Vite + TanStack Router + TypeScript + pnpm
- **Mobile App**: Expo SDK 57 + Expo Router + React Native 0.86 + TypeScript
- **Web API**: ASP.NET Core Minimal APIs (.NET 10)
- **Worker**: Azure Functions isolated worker (C#) + vision model (Gemma 3 via Docker Model Runner)
- **Shared Data**: EF Core with SQL Server provider (`libs/data/`)
- **Dev Container**: `mcr.microsoft.com/devcontainers/base:bookworm` with Node.js, .NET, Azure Functions Core Tools, and GitHub CLI as features

## Build & Run Commands

```bash
# Restore all .NET projects
dotnet restore SnapSort.slnx

# Run the API
cd apps/web-api && dotnet run

# Run the Worker
cd apps/worker && dotnet run

# Install Node dependencies for every workspace package
pnpm install   # from the repo root — one pnpm workspace covers web-app and mobile

# Run the web app dev server
pnpm web        # or: pnpm --filter web-app dev

# Run the mobile app (Expo Go on a phone, via cloudflared + Expo tunnel)
pnpm mobile:tunnel   # or: pnpm mobile  for LAN-only

# Formatting (Prettier for web/docs, dotnet format for C#)
pnpm format
pnpm format:check

# Verify parallel-worktree isolation still holds
scripts/check-worktree-isolation.sh

# Tests
dotnet test SnapSort.slnx          # all
dotnet test tests/unit             # unit only
dotnet test tests/integration      # integration only

# Create an EF migration (from repo root)
dotnet ef migrations add <Name> --project libs/data --startup-project apps/web-api

# Apply EF migrations
dotnet ef database update --project libs/data --startup-project apps/web-api
```

## Connection Strings

Connection strings are passed as environment variables on the devcontainer service in `docker-compose.yml` using the `ConnectionStrings__*` pattern:

- `ConnectionStrings__AppDb` — SQL Server (app-mssql container, port 1433)
- `ConnectionStrings__ServiceBus` — Azure Service Bus Emulator (port 5672)
- `ConnectionStrings__AzureStorage` — Azurite (ports 10000-10002)

Both the API and Worker read these from the environment. Do NOT hardcode connection strings in appsettings.json — they come from the compose environment.

## Vision Model

The Worker classifies AND describes each image in a single call to a local vision
model (Gemma 3 4B) served by Docker Model Runner over an OpenAI-compatible
`/v1/chat/completions` endpoint. The response is constrained with a JSON schema
(`response_format: json_schema`), so it comes back as `{label, confidence, description}`.

Configured via environment on the devcontainer service in `docker-compose.yml`:

- `VisionModel__Endpoint` — Docker Model Runner base URL (port 12434)
- `VisionModel__Model` — model id, e.g. `ai/gemma3:4B-Q4_K_M`

The Worker fails at startup if these are missing. `confidence` is the model's own
self-assessment, not a calibrated probability — the UIs show it as a band
(high/medium/low), not a percentage.

## Infrastructure Services

All run as Docker containers via `.devcontainer/docker-compose.yml`:

- `app-mssql` — SQL Server 2022 for the app database (password: `App_Passw0rd!`)
- `servicebus-mssql` — Dedicated SQL Server for Service Bus Emulator (password: `ServiceBus0!`)
- `servicebus-emulator` — Azure Service Bus Emulator with `image-processing` queue
- `azurite` — Azure Storage Emulator (well-known dev account key)

## Workspace Mount

Compose mounts the worktree's **parent** at `/workspaces`, and `workspaceFolder` is
`/workspaces/${localWorkspaceFolderBasename}`. This is required by the bare-repo layout:
a worktree's `.git` is a file pointing at `<parent>/.bare/worktrees/<name>`, which sits
outside the worktree, so mounting only the worktree leaves git unable to resolve its own
git directory. Do not change this back to `..:/workspace`.

Worktrees must also be created with `--relative-paths` (the host scripts do this) — an
absolute host path in `.git` does not exist inside the container.

## Networking

Compose publishes **no** ports to the host. Services reach each other by compose
service name on the internal network (`app-mssql:1433`, `servicebus-emulator:5672`,
`azurite:10000`), and VS Code forwards only the dev ports (5173, 5000, 7071, 8081,
19000-19002) out of the container. Do not add `ports:` mappings — the absence of
published ports is what lets several worktrees run full stacks simultaneously.

## GitHub CLI

`gh` is installed via the `github-cli` dev container feature. Compose bind-mounts
the host's `~/.config/gh` into the container, so `gh auth login` on the host
carries into every worktree's container — no separate login per container, and
the auth survives rebuilds because it lives on the host, not in the image.

On macOS the token must be in `~/.config/gh/hosts.yml` for this to work; a
Keychain-stored token does not cross the mount. `gh auth login --insecure-storage`
on the host puts it there.

## Git Identity

The container does NOT rely on VS Code's `dev.containers.copyGitConfig` to get a
commit author. That is a per-machine editor setting, and even when it is on it
copies `~/.gitconfig` verbatim — so an identity kept in XDG
(`~/.config/git/config`) or reached through an `includeIf` never arrives. Either
way the symptom is the same: `git commit` fails inside the container with
"unable to auto-detect email address".

Instead `.devcontainer/init.sh` asks the host's git for the _resolved_
`user.name` and `user.email` (from the worktree, so repo-conditional identities
work), writes them to `.devcontainer/.env`, and compose passes them as
`GIT_USER_NAME` / `GIT_USER_EMAIL`. `.devcontainer/configure-git.sh` applies them
to the container's global config on `postCreateCommand`.

Consequences worth knowing:

- The host is the source of truth. Change your identity there and rebuild; do
  not `git config --global` inside the container, since that dies with it.
- Do not set `user.name`/`user.email` in the repo's local config either. In the
  bare layout that is `.bare/config`, which every worktree shares, and local
  overrides global — so it would silently shadow this mechanism everywhere.
- Both scripts warn loudly when the host has no identity configured, rather than
  letting the first commit fail with git's own message, which misleadingly
  points at `--global` as the fix.

## Parallel Worktrees

Each git worktree gets its own dev container and its own sidecar services.
`.devcontainer/init.sh` runs on the host as `initializeCommand` and writes
`WORKTREE_NAME` for compose; volumes are per-project except the deliberately shared,
`external: true` Claude config volume. See `docs/devcontainer-worktrees.md` before
changing anything in `.devcontainer/`.

`scripts/check-worktree-isolation.sh` asserts the invariants that make this work
(no published host ports, no `appPort`, per-project volumes, relative worktree paths).
Run it after touching anything in `.devcontainer/` — the static pass works inside the
container; the live pass needs the docker CLI, so run it on the host.

## Version Pinning

Everything that can drift is pinned in exactly one place:

- `global.json` — the .NET SDK
- `Directory.Build.props` — the target framework and language settings for all five projects
- `Directory.Packages.props` — every NuGet version (Central Package Management). The `.csproj`
  files carry `<PackageReference>` with no `Version` attribute, and a build fails if one
  reintroduces it. Keep the EF Core entries in step with `.config/dotnet-tools.json`.
- `.devcontainer/devcontainer-lock.json` — every dev container feature, by digest
- `.devcontainer/docker-compose.yml` — every emulator image, by exact tag, never `:latest`

`packages.lock.json` files are generated on restore and committed. Generation only —
`RestoreLockedMode` is not on, so a version bump does not fail a local restore.

## Formatting and Commits

Prettier and ESLint are real dependencies, not editor extensions, and run on staged files
through husky + lint-staged. C# is formatted by `dotnet format` against the same
`.editorconfig` the IDE reads.

One trap worth knowing: `dotnet format --include` silently matches nothing when given
absolute paths — it reports "Formatted 0 of N files" and exits 0. lint-staged passes
absolute paths, so `lint-staged.config.js` converts them to relative first.

Commit messages are Conventional Commits, enforced by commitlint on `commit-msg`.

## Coding Conventions

- .NET projects use minimal APIs pattern (no controllers)
- Use `record` types for DTOs and messages
- EF Core migrations live in `libs/data/Migrations/`
- Both API and Worker share models/DbContext from `libs/data`
- Web app uses TanStack Router file-based routing in `src/routes/`
- Mobile app uses Expo Router file-based routing in `app/`; shared API client in `src/api.ts`
- Mobile Metro config must not set `disableHierarchicalLookup` — it breaks pnpm resolution (see the comment in `apps/mobile/metro.config.js`)
- pnpm for all Node.js package management; one workspace at the repo root (`pnpm-workspace.yaml`), one lockfile, `pnpm --filter <pkg>` to target an app
- Prettier for formatting, ESLint for linting (web app)
