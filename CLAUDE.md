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
- **Mobile App**: Expo SDK 54 + Expo Router + React Native 0.81 + TypeScript
- **Web API**: ASP.NET Core Minimal APIs (.NET 10)
- **Worker**: Azure Functions isolated worker (C#) + vision model (Gemma 3 via Docker Model Runner)
- **Shared Data**: EF Core with SQL Server provider (`libs/data/`)
- **Dev Container**: `mcr.microsoft.com/devcontainers/base:bookworm` with Node.js, .NET, and Azure Functions Core Tools as features

## Build & Run Commands

```bash
# Restore all .NET projects
dotnet restore SnapSort.slnx

# Run the API
cd apps/web-api && dotnet run

# Run the Worker
cd apps/worker && func start

# Install Node dependencies for every workspace package
pnpm install   # from the repo root — one pnpm workspace covers web-app and mobile

# Run the web app dev server
pnpm web        # or: pnpm --filter web-app dev

# Run the mobile app (Expo Go on a phone, via cloudflared + Expo tunnel)
pnpm mobile:tunnel   # or: pnpm mobile  for LAN-only

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

## Networking

Compose publishes **no** ports to the host. Services reach each other by compose
service name on the internal network (`app-mssql:1433`, `servicebus-emulator:5672`,
`azurite:10000`), and VS Code forwards only the dev ports (5173, 5000, 7071, 8081,
19000-19002) out of the container. Do not add `ports:` mappings — the absence of
published ports is what lets several worktrees run full stacks simultaneously.

## Parallel Worktrees

Each git worktree gets its own dev container and its own sidecar services.
`.devcontainer/init.sh` runs on the host as `initializeCommand` and writes
`WORKTREE_NAME` for compose; volumes are per-project except the deliberately shared,
`external: true` Claude config volume. See `docs/devcontainer-worktrees.md` before
changing anything in `.devcontainer/`.

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
