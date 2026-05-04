# Plan: Parallel-worktree dev container setup (bare-repo layout)

> **Status:** Plan agreed; execution not yet started.
> Companion to `devcontainer-migration.md` (the reference doc from Claude
> desktop). This file captures the agreed plan for *this* repo so it
> survives container rebuilds and Claude Code session switches.

## Context

Goal: run multiple Claude Code instances simultaneously, each on its own
branch in its own git worktree, each in its own dev container with
isolated sidecar services. Today, hardcoded host port mappings on every
sidecar (SQL, Azurite, Service Bus) collide on a second `docker compose
up`, blocking parallel use, and the repo is a normal checkout where
`main` is privileged over other worktrees.

Per user direction we'll restructure into the **bare-repo + sibling-
worktrees layout** so no worktree is "primary" — `main` is just another
worktree under a parent directory that contains a bare clone.

## Audit summary (current state)

- `.devcontainer/devcontainer.json` — compose-based, no `runArgs`, no
  hardcoded container name. `forwardPorts` + `portsAttributes` already
  handle app-side ports (5173, 5000, 7071, 8081, 19000-19002) via VS
  Code's auto-allocation.
- `.devcontainer/docker-compose.yml` — five services. Hardcoded host
  port mappings on every sidecar (1433, 1434, 5672, 5300, 10000-10002).
  No top-level `name:`. Named volumes: `bashhistory`,
  `claude-code-config`, `app-mssql-data`, `servicebus-mssql-data`,
  `azurite-data`.
- Workspace bind mount is `..:/workspace:cached` — relative to
  `.devcontainer/`, so each worktree mounts its own directory.
- Internal service DNS (`app-mssql`, `azurite`, `servicebus-emulator`)
  is hardcoded in compose env and `tests/integration/ApiFixture.cs`.
  Each compose stack gets its own network → DNS resolves locally. Fine.
- `host.docker.internal:12434` (VisionModel) — single shared host
  service, acceptable to share across worktrees.
- `scripts/`: `welcome.sh`, `seed.sh`, `reset.sh`, `mobile-tunnel.sh`.
  Style: `#!/usr/bin/env bash`, `set -euo pipefail`, ANSI escapes.
- No existing partial worktree implementation.

## Target layout

```
~/code/snapsort/                ← parent directory (was the checkout)
├── .bare/                      ← bare git repo (was .git in old layout)
├── .git                        ← one-line file: "gitdir: ./.bare"
├── main/                       ← worktree for main branch
│   ├── .devcontainer/
│   ├── apps/
│   ├── scripts/
│   └── ...
├── feat-foo/                   ← worktree for feat/foo branch
└── bugfix-bar/                 ← worktree for bugfix/bar branch
```

## How parallelism works

**Internal vs. host networking.** Each compose project gets its own
private Docker network. Service hostnames (`app-mssql`, `azurite`,
`servicebus-emulator`) are DNS names that only resolve on that
project's network, and the existing connection strings already use
those hostnames — never `localhost:port`. So `Server=app-mssql` in
worktree A and worktree B point to different containers, both happily
listening on container-internal port 1433. Container-internal ports
never touch the host and never collide. The collision risk is purely
on the *host side*, from `ports:` mappings — which we drop.

**Project naming.** Compose's directory-based default project naming
has been inconsistent across versions (especially when the compose
file lives in `.devcontainer/`). Rather than rely on it, we pass an
explicit `WORKTREE_NAME` from an `initializeCommand` and use it in
`name:` at the top of the compose file. Each worktree gets a
deterministic project name (`snapsort-main`, `snapsort-feat-foo`,
etc.) regardless of compose version.

## Decisions confirmed

- **Layout:** bare-repo + sibling-worktrees.
- **Workflow:** helper scripts + VS Code tasks as primary; document
  Claude Code's built-in `Agent({isolation: "worktree"})` as an
  alternative for short-lived sub-agent work.
- **`claude-code-config` volume:** shared across worktrees (pinned
  name, independent of compose project prefix).
- **Sidecar host ports:** drop entirely (deferred re-add as future
  item if host tooling access matters).
- **Per-worktree window title:** yes, via `${workspaceFolderBasename}`
  in `.vscode/settings.json` — automatic, no per-worktree templating.

## Execution sequence (inside vs. outside the dev container)

The work splits into three phases by where it must run:

### Phase A — Inside the current dev container (file edits + commit)

All file changes land on the bind-mounted workspace, so editing from
inside the container is fine and convenient (existing tooling
available). Nothing here disrupts the running container until a
rebuild happens.

1. Edit `.devcontainer/docker-compose.yml`, `.devcontainer/devcontainer.json`.
2. Create `.devcontainer/init.sh` (executable).
3. Update `.gitignore`.
4. Create `.vscode/settings.json` and `.vscode/tasks.json`.
5. Reword `scripts/welcome.sh`.
6. Create `scripts/new-worktree.sh`, `scripts/remove-worktree.sh`,
   `scripts/migrate-to-bare-layout.sh` (all executable).
7. Create `docs/devcontainer-worktrees.md`.
8. Commit on `main`. **Do not rebuild yet** — the new compose `name:`
   uses `WORKTREE_NAME` which won't be set until after migration.

### Phase B — On the host (structural migration)

Cannot run inside the container: the bind mount is anchored on the
directory we're restructuring.

1. Stop / close the dev container ("Reopen Folder Locally" or close
   VS Code).
2. From the host shell, in the parent directory of the current
   checkout, run `scripts/migrate-to-bare-layout.sh` (path will be
   inside the soon-to-be-renamed checkout, so copy it out first or
   run via `bash <path>`).
3. Verify the new layout: `.bare/` directory and `.git` pointer at
   the parent; `<parent>/main/` is a worktree with the full repo.
4. Delete the old checkout directory.

### Phase C — In the new layout (verify + test parallelism)

1. `code <parent>/main` → Reopen in Container.
2. Confirm the rebuilt container works: sidecars up, API at `:5000`,
   web app at `:5173`, `scripts/seed.sh` + `scripts/reset.sh` still
   pass. Window title shows `[main]`.
3. Run `scripts/new-worktree.sh test/parallel`. Open the new path in
   a second VS Code window → Reopen in Container.
4. Confirm both run simultaneously (see Verification below). Then
   `scripts/remove-worktree.sh test/parallel` to confirm cleanup.

## One-time migration script (`scripts/migrate-to-bare-layout.sh`)

Runs **on the host shell only**.

- Verify `git status` clean and `git log @{u}..` empty (refuse otherwise).
- Capture current branch and remote URL.
- `git clone --bare <remote> .bare` next to the existing checkout.
- Write `.git` pointer file: `gitdir: ./.bare`.
- Configure the bare repo's fetch refspec
  (`+refs/heads/*:refs/remotes/origin/*`) so worktree adds against
  `origin/...` work as expected.
- `git worktree add <branch> <branch>` for the current branch (and
  others if requested).
- Print instructions to delete the old checkout and `code <new-path>/<branch>`.
- Idempotent-checked, refuses destructive actions without `--confirm`.

## Changes (file-by-file)

### `.devcontainer/docker-compose.yml`

- Add at the top:
  ```yaml
  name: snapsort-${WORKTREE_NAME:-default}
  ```
- Remove `ports:` blocks from `app-mssql`, `servicebus-mssql`,
  `servicebus-emulator`, `azurite`. Sidecars stay reachable via
  internal DNS, which is how the app already talks to them.
- Pin `claude-code-config` to a static cross-project name:
  ```yaml
  volumes:
    claude-code-config:
      name: claude-code-config-shared
    bashhistory:
    app-mssql-data:
    servicebus-mssql-data:
    azurite-data:
  ```
- Leave the other named volumes unpinned (compose prefixes per project).

### `.devcontainer/devcontainer.json`

```jsonc
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/init.sh",
"runArgs": ["--hostname", "${localWorkspaceFolderBasename}"]
```

### `.devcontainer/init.sh` (new, executable)

Portable bash. Writes `.devcontainer/.env`:

```
WORKTREE_NAME=<basename of workspace folder>
```

Idempotent; overwrites each run.

### `.gitignore`

Add `.devcontainer/.env`.

### `.vscode/settings.json` (new)

```jsonc
{
  "window.title": "${dirty}${activeEditorShort}${separator}${rootName} [${workspaceFolderBasename}]"
}
```

### `.vscode/tasks.json` (new)

Three tasks wrapping the scripts:

- **Worktree: New** — prompts for branch + optional base; runs
  `scripts/new-worktree.sh`.
- **Worktree: Remove** — prompts for branch; runs
  `scripts/remove-worktree.sh`.
- **Worktree: Open in New Window** — lists existing worktrees via
  `git worktree list --porcelain`; runs `code <path>`.

`presentation.reveal: always` so output is visible.

### `scripts/welcome.sh`

Reword the printed `http://localhost:5173` and `http://localhost:5000`
lines: clarify these URLs are valid *inside* the container; on the
host, use VS Code's Ports panel.

### `scripts/new-worktree.sh` (new, executable)

Usage: `scripts/new-worktree.sh <branch> [base-branch]`

- Walks up to find `.bare/` (refuses if not found, points at the
  migration script).
- Computes target as `<parent>/<branch-slug>` (slug: `/` → `-`).
- Refuses if a worktree at that path or for that branch exists.
- `git worktree add` with `-b` for new branches, plain checkout for
  existing.
- Prints next steps: `code <path>` → Reopen in Container, or
  `cd <path> && claude`.

### `scripts/remove-worktree.sh` (new, executable)

Usage: `scripts/remove-worktree.sh <branch>`

- Validates: bare-repo layout detected, target worktree exists,
  target is not the current worktree.
- Derives compose project name from the worktree's directory basename.
- `docker compose -p <project> down -v` against the worktree's
  compose file (`--project-directory <worktree>/.devcontainer`).
- `git worktree remove <path>`.
- Lists any remaining `<project>_*` volumes for manual review (does
  **not** auto-`docker volume rm`).

### `scripts/migrate-to-bare-layout.sh` (new, executable, host-only)

See "One-time migration script" above.

### `docs/devcontainer-worktrees.md` (new)

- **Why** — parallel Claude sessions on independent branches.
- **Layout** — diagram + why no worktree is privileged.
- **One-time migration** — walked through with prerequisites and
  rollback.
- **Quickstart** — `scripts/new-worktree.sh feat/foo` → VS Code →
  Reopen in Container → `claude`. Or task "Worktree: New".
- **How isolation works** — internal DNS, shared
  `claude-code-config`, no host ports, per-window title.
- **Alternative** — `Agent({isolation: "worktree"})` for short-lived
  sub-agents.
- **Cleanup** — `scripts/remove-worktree.sh feat/foo`.
- **Gotchas** — branch-checkout-once rule, RAM/disk per worktree,
  per-worktree `node_modules` / `bin/obj`, shared
  `claude-code-config` race risk.
- **Future** — env-driven host port re-add for SSMS / Azure Storage
  Explorer; `scripts/list-worktrees.sh`.

## Files modified / created

- `.devcontainer/docker-compose.yml` — add explicit `name:`, drop
  sidecar ports, pin `claude-code-config` volume name.
- `.devcontainer/devcontainer.json` — add `initializeCommand` and
  `runArgs` for hostname.
- `.devcontainer/init.sh` — new, executable.
- `.gitignore` — add `.devcontainer/.env`.
- `.vscode/settings.json` — new, sets window title.
- `.vscode/tasks.json` — new.
- `scripts/welcome.sh` — reword localhost lines.
- `scripts/new-worktree.sh` — new, executable.
- `scripts/remove-worktree.sh` — new, executable.
- `scripts/migrate-to-bare-layout.sh` — new, executable (host-side).
- `docs/devcontainer-worktrees.md` — new.

No changes to app code.

## Verification

1. **Pre-migration sanity:** `git status` clean, `git log @{u}..` empty.
2. **Run migration script** from host shell. Confirm `.bare/` + `.git`
   pointer at parent; `<parent>/main/` is a worktree.
3. **Single worktree still works:** open `<parent>/main/` → Reopen in
   Container. Sidecars up; API at `:5000`; web app at `:5173`;
   `scripts/seed.sh` + `scripts/reset.sh` work. Title shows `[main]`.
4. **Parallel:** `scripts/new-worktree.sh test/parallel` → second VS
   Code window → Reopen in Container. Confirm:
   - `docker ps` shows distinct project prefixes.
   - `docker volume ls` shows separate `*_app-mssql-data` per project,
     plus one shared `claude-code-config-shared`.
   - Each container's API connects to its own DB.
   - Window titles read `[main]` and `[test-parallel]`.
5. **Cleanup:** `scripts/remove-worktree.sh test/parallel`. Directory
   gone, containers stopped/removed, per-stack volumes dropped,
   `claude-code-config-shared` preserved.
6. **VS Code tasks:** Command Palette → "Tasks: Run Task" → all three
   appear and work.

## Out of scope

- Re-adding env-driven host port mappings for sidecars (future).
- `scripts/list-worktrees.sh` showing container/volume status per
  worktree (future polish).

## Resume notes for context switches

- This plan is at `/workspace/devcontainer-migration-plan.md` (or
  `<worktree>/devcontainer-migration-plan.md` after migration).
- The original Claude desktop reference is in
  `devcontainer-migration.md`.
- Phase A work is editable from inside the current dev container.
- Phase B (`scripts/migrate-to-bare-layout.sh`) **must** run on the
  host shell — copy or read the script before stopping the container.
- After migration, the working directory becomes
  `<parent>/main/` (or whichever branch's worktree you opened).
