# CLAUDE.md

## Project Overview

SnapSort is a polyglot monorepo image classification app. It demonstrates dev container composition with Azure emulation for a lunch-and-learn.

## Directory Conventions

- `apps/` — deployable code units (web-app, web-api, worker)
- `libs/` — shared libraries (data layer with EF Core models, DbContext, migrations)
- `.devcontainer/` — all dev container configuration (Dockerfile, docker-compose.yml, devcontainer.json)
- Solution file `SnapSort.sln` lives at repo root and references all .csproj files

## Tech Stack

- **Web App**: React 19 + Vite + TanStack Router + TypeScript + pnpm
- **Web API**: ASP.NET Core Minimal APIs (.NET 9)
- **Worker**: Azure Functions isolated worker (C#) + ML.NET + MobileNet v2 ONNX
- **Shared Data**: EF Core with SQL Server provider (`libs/data/`)
- **Dev Container**: `mcr.microsoft.com/devcontainers/base:bookworm` with Node.js and .NET as features

## Build & Run Commands

```bash
# Restore all .NET projects
dotnet restore SnapSort.sln

# Run the API
cd apps/web-api && dotnet run

# Run the Worker
cd apps/worker && func start

# Install web app dependencies
cd apps/web-app && pnpm install

# Run the web app dev server
cd apps/web-app && pnpm dev

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

## Infrastructure Services

All run as Docker containers via `.devcontainer/docker-compose.yml`:

- `app-mssql` — SQL Server 2022 for the app database (password: `App_Passw0rd!`)
- `servicebus-mssql` — Dedicated SQL Server for Service Bus Emulator (password: `ServiceBus0!`)
- `servicebus-emulator` — Azure Service Bus Emulator with `image-processing` queue
- `azurite` — Azure Storage Emulator (well-known dev account key)

## Coding Conventions

- .NET projects use minimal APIs pattern (no controllers)
- Use `record` types for DTOs and messages
- EF Core migrations live in `libs/data/Migrations/`
- Both API and Worker share models/DbContext from `libs/data`
- Web app uses TanStack Router file-based routing in `src/routes/`
- pnpm for all Node.js package management
- Prettier for formatting, ESLint for linting (web app)
