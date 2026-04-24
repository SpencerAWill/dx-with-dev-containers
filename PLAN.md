# SnapSort — Implementation Plan

## Context

This repo is a lunch-and-learn demo showing how dev container composition + Azure emulation creates a fully isolated local dev environment for a polyglot monorepo. We'll build an image classification application across 3 projects, backed by Azure emulators, all orchestrated via Docker Compose and a single dev container.

## Application Domain: Image Classification

Users upload images through a React UI. The API stores the image in Blob Storage, saves metadata in SQL Server, and publishes a Service Bus message. A Worker Function picks up the message, downloads the image from blob storage, runs it through a pre-trained MobileNet v2 ONNX model via ML.NET, and writes the classification label + confidence score back to SQL.

| Component | Tech | Role |
|---|---|---|
| Web App | React 19 + Vite + TanStack Router + pnpm | Upload form, image gallery with classification results |
| Web API | ASP.NET Core Minimal APIs (.NET 9) | Image upload (blob + SQL + Service Bus), CRUD endpoints |
| Worker | Azure Functions isolated worker (C#) | Service Bus trigger, ML.NET + MobileNet ONNX inference, updates SQL |

| Azure Service | Emulator | Purpose |
|---|---|---|
| Blob Storage | Azurite | Stores uploaded images |
| Service Bus | Service Bus Emulator | Carries `image-uploaded` messages from API to Worker |
| SQL Database | SQL Server 2022 container | Stores image metadata, classification results |

## Dev Container Architecture: Single Polyglot Container

One dev container built on `mcr.microsoft.com/devcontainers/base:bookworm` with Node.js and .NET installed as dev container features.

### Dockerfile (`.devcontainer/Dockerfile`)
- Base: `mcr.microsoft.com/devcontainers/base:bookworm`
- Install `fzf`, `jq` via apt
- Persist bash history via named volume
- zsh-in-docker for terminal UX
- Claude Code pre-installed
- User: `vscode`, shell: zsh, workdir: `/workspace`

### devcontainer.json (`.devcontainer/devcontainer.json`)
- `dockerComposeFile: "docker-compose.yml"`
- `service: "devcontainer"`
- Features: `node:1`, `dotnet:2`, `azure-functions-core-tools:1`
- Extensions: eslint, prettier, csdevkit, azure functions, azure storage, mssql, servicebus-emulator-explorer, editorconfig
- Settings: formatOnSave, prettier default, eslint codeActionsOnSave, zsh default terminal
- `remoteUser: "vscode"`, `workspaceFolder: "/workspace"`
- Forward ports: 5173 (Vite), 5000 (API), 7071 (Azure Functions)
- `postCreateCommand`: `{ "node": "cd apps/web-app && pnpm install", "dotnet": "dotnet restore SnapSort.sln" }`

### docker-compose.yml (`.devcontainer/docker-compose.yml`)
5 services:

| Service | Image | Ports | Purpose |
|---|---|---|---|
| `devcontainer` | Built from Dockerfile | 5173, 5000, 7071 | Polyglot dev container (Node.js + .NET) |
| `app-mssql` | `mcr.microsoft.com/mssql/server:2022-latest` | 1433 | Application SQL database |
| `servicebus-mssql` | `mcr.microsoft.com/mssql/server:2022-latest` | 1434 | Service Bus Emulator's dedicated SQL |
| `servicebus-emulator` | `mcr.microsoft.com/azure-messaging/servicebus-emulator` | 5672, 5300 | Azure Service Bus Emulator |
| `azurite` | `mcr.microsoft.com/azure-storage/azurite` | 10000-10002 | Azure Storage Emulator |

### Connection Strings (environment variables on devcontainer)
```
ConnectionStrings__AppDb=Server=app-mssql;Database=SnapSort;User Id=sa;Password=App_Passw0rd!;TrustServerCertificate=true
ConnectionStrings__ServiceBus=Endpoint=sb://servicebus-emulator;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;
ConnectionStrings__AzureStorage=DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;
```

## Directory Structure (Nx-like)

```
better-dx-with-dev-containers/
├── README.md
├── PLAN.md
├── CLAUDE.md
├── .gitignore
├── .editorconfig
├── SnapSort.sln                        (references all .csproj files)
├── .devcontainer/
│   ├── devcontainer.json
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── servicebus-config.json
├── apps/                               (deployable code units)
│   ├── web-app/                        (React 19 + Vite + TanStack Router)
│   │   ├── package.json
│   │   ├── pnpm-lock.yaml
│   │   ├── vite.config.ts
│   │   ├── tsconfig.json
│   │   ├── index.html
│   │   └── src/
│   │       ├── main.tsx
│   │       ├── routeTree.gen.ts
│   │       ├── routes/
│   │       │   ├── __root.tsx
│   │       │   ├── index.tsx           (gallery view)
│   │       │   └── upload.tsx          (upload form)
│   │       └── components/
│   ├── web-api/                        (ASP.NET Core Minimal APIs)
│   │   ├── WebApi.csproj               (references libs/data)
│   │   ├── Program.cs
│   │   ├── appsettings.json
│   │   ├── appsettings.Development.json
│   │   └── Endpoints/
│   │       └── ImageEndpoints.cs
│   └── worker/                         (Azure Functions isolated worker)
│       ├── Worker.csproj               (references libs/data)
│       ├── Program.cs
│       ├── host.json
│       ├── local.settings.json
│       └── Functions/
│           └── ClassifyImageFunction.cs
└── libs/                               (shared libraries)
    └── data/                           (EF Core models + DbContext + migrations)
        ├── Data.csproj
        ├── AppDbContext.cs
        ├── Models/
        │   └── Image.cs
        └── Migrations/
```

The `libs/data` project contains the `Image` model, `AppDbContext`, and EF Core migrations. Both `apps/web-api` and `apps/worker` reference it via `<ProjectReference>`.

## Implementation Phases

### Phase 1: Dev Container Infrastructure
Create all the dev container plumbing from scratch.

**Files to create:**
- `.devcontainer/Dockerfile`
- `.devcontainer/docker-compose.yml`
- `.devcontainer/devcontainer.json`
- `.devcontainer/servicebus-config.json`
- `.gitignore`
- `.editorconfig`

**Verify:** Open repo in VS Code, "Reopen in Container". All 5 containers start. Connect to SQL Server (`app-mssql` on 1433). Azurite responds on 10000. Service Bus emulator logs show the queue created.

### Phase 2: Shared Data Library + Web API Skeleton

**Work:**
- Create `SnapSort.sln` at repo root
- Create `libs/data/` as a class library (`dotnet new classlib`)
  - Add NuGet: `Microsoft.EntityFrameworkCore.SqlServer`, `Microsoft.EntityFrameworkCore.Design`
  - Create `Image` model: Id (Guid), OriginalFileName, ContentType, BlobUri, Status (enum: Uploaded/Processing/Classified/Failed), ClassificationLabel (nullable), Confidence (nullable), UploadedAt, ClassifiedAt (nullable)
  - Create `AppDbContext` with `DbSet<Image>`
- Create `apps/web-api/` as ASP.NET Core Minimal API (`dotnet new webapi --use-minimal-apis`)
  - Add project reference to `libs/data/Data.csproj`
  - Create EF migration (using the API as the startup project)
  - Add endpoints: `GET /api/images` (list all), `GET /api/images/{id}` (single), health check
  - Read connection string from `ConnectionStrings__AppDb` environment variable
  - Run migration on startup (for dev simplicity)
- Add both projects to `SnapSort.sln`

**Verify:** `dotnet run` inside container from `apps/web-api/`, `GET /api/images` returns `[]`.

### Phase 3: Blob Storage + Upload Endpoint

**Work:**
- Add NuGet to `apps/web-api`: `Azure.Storage.Blobs`
- Add `POST /api/images` — accepts multipart file upload, stores blob in `images` container in Azurite, creates SQL row with status `Uploaded`, returns the created image
- Add `GET /api/images/{id}/download` — streams the blob back
- Read connection string from `ConnectionStrings__AzureStorage` environment variable

**Verify:** Upload an image via curl/REST Client. Confirm blob in Azurite, SQL row created.

### Phase 4: Service Bus Integration (API Side)

**Work:**
- Add NuGet to `apps/web-api`: `Azure.Messaging.ServiceBus`
- After upload in `POST /api/images`, publish `ImageUploaded` message to `image-processing` queue
- Message body: `{ "imageId": "...", "blobUri": "..." }`
- Read connection string from `ConnectionStrings__ServiceBus` environment variable

**Verify:** Upload an image. Check Service Bus emulator for the queued message.

### Phase 5: Worker Function + ML.NET Classification

**Work:**
- Scaffold `apps/worker/` as Azure Functions isolated worker
- Add project reference to `libs/data/Data.csproj`
- Add NuGet: `Microsoft.Azure.Functions.Worker.Extensions.ServiceBus`, `Azure.Storage.Blobs`, `Microsoft.ML`, `Microsoft.ML.OnnxRuntime`
- Download MobileNet v2 ONNX model (include as build asset or download on first run)
- Create `ClassifyImageFunction`:
  1. Service Bus trigger on `image-processing` queue
  2. Deserialize message to get imageId + blobUri
  3. Download image from Azurite blob storage
  4. Run ML.NET inference with MobileNet v2
  5. Update SQL row: set ClassificationLabel, Confidence, Status = Classified, ClassifiedAt
- Configure `local.settings.json` with emulator connection strings
- Add to `SnapSort.sln`

**Verify:** Run API + Worker in two terminals. Upload an image. Worker classifies it. `GET /api/images/{id}` returns label + confidence.

### Phase 6: React Web App

**Work:**
- `pnpm create vite@latest web-app --template react-ts` in `apps/`
- Add TanStack Router, configure file-based routing
- Configure Vite proxy: `/api` -> `http://localhost:5000`
- Routes:
  - `/` — Gallery grid with thumbnails, classification labels, confidence badges, status indicators
  - `/upload` — Drag-and-drop upload form, progress, redirect to gallery
- Simple, clean UI

**Verify:** Upload image in browser. See it in gallery. Watch status change to "Classified". Label and confidence displayed.

### Phase 7: Polish
- Architecture diagram (Mermaid) in README
- Comments in compose/devcontainer files
- Optional `.vscode/launch.json` for debugging

## Key Design Decisions

1. **Single polyglot container** — `base:bookworm` with Node.js + .NET as features. One VS Code window.
2. **Two SQL Server instances** — Service Bus Emulator gets its own. App gets a clean one. Avoids conflicts.
3. **ML.NET + MobileNet v2 ONNX** — in-process C# inference, no external API, 1000 ImageNet categories.
4. **Connection strings as env vars** — `ConnectionStrings__*` pattern on the devcontainer service.
5. **pnpm** for the web app.
6. **EF Core migrations run on startup** — acceptable for dev.
7. **`libs/data` shared library** — avoids duplicating the data layer between API and Worker.
