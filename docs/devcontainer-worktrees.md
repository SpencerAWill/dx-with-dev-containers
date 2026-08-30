# Parallel dev containers via git worktrees

Run multiple SnapSort dev containers at the same time, each on a
different branch, each with its own isolated SQL Server, Service Bus,
and Azurite — for working on independent features in parallel (e.g.
multiple Claude Code instances).

## Why

A single dev container can't host two branches. With the bare-repo +
sibling-worktrees layout below, every branch you care about gets its
own directory, its own VS Code window, its own dev container, and its
own sidecar services. The compose project name is derived from the
worktree directory, so networks and volumes don't collide.

## Layout

```
~/code/snapsort/                   ← parent directory
├── .bare/                         ← bare git repo (shared across worktrees)
├── .git                           ← pointer file: "gitdir: ./.bare"
├── main/                          ← worktree for main
│   ├── .devcontainer/
│   ├── apps/
│   └── ...
├── feat-foo/                      ← worktree for feat/foo
└── bugfix-bar/                    ← worktree for bugfix/bar
```

No worktree is privileged. `main` is just another directory.

## One-time migration from a regular checkout

If you currently have a normal `git clone` of SnapSort, convert it to
the bare-repo layout once:

```bash
# From the host shell, inside your existing checkout:
./scripts/migrate-to-bare-layout.sh            # dry run, prints the plan
./scripts/migrate-to-bare-layout.sh --confirm  # builds a sibling staging dir
```

The script is non-destructive — it builds a `~/code/snapsort-bare-layout/`
sibling and prints `mv` commands for you to swap layouts manually after
verifying. **Stop the dev container first** (rebinding paths under a
running bind mount confuses Docker).

Prerequisites: clean working tree, no unpushed commits.

## Quickstart

After migration:

```bash
# From the host shell (any worktree's scripts/ copy will do):
cd ~/code/snapsort/main
./scripts/new-worktree.sh feat/auth-rework        # new branch from HEAD
./scripts/new-worktree.sh hotfix/db origin/main   # new branch from a base
./scripts/new-worktree.sh existing-branch         # check out an existing branch
```

Then open the new worktree:

```bash
code ~/code/snapsort/feat-auth-rework
```

In VS Code: **Dev Containers: Reopen in Container**. The container
build sets the compose project name from the worktree directory
(`snapsort-feat-auth-rework`), so it gets its own isolated network,
sidecars, and per-project volumes.

You can now run a Claude Code session in this worktree's terminal
independently of any other worktree.

## How isolation works

- **Connection strings already use service hostnames.** The app reads
  `Server=app-mssql`, `Endpoint=sb://servicebus-emulator`, etc. —
  never `localhost:port`. Each compose project gets its own private
  Docker network, and these hostnames resolve locally on each
  network. Worktree A's `app-mssql` and worktree B's `app-mssql` are
  two different containers that never see each other.
- **No host port mappings on sidecars.** Container-internal ports
  (1433, 5672, 10000-10002, etc.) never touch the host, so nothing
  collides at the host level. App-side ports (5173, 5000, 7071,
  8081, ...) are still listed in `forwardPorts` and VS Code
  auto-allocates a free host port per worktree window — see the
  Ports panel in each window for the host URL.
- **Compose project name comes from VS Code.** The dev containers
  extension generates a unique compose project name per workspace
  folder path. Two worktrees with different paths therefore get
  distinct project namespaces (network, container names, volume
  prefix) automatically — we don't (and can't) set a top-level
  `name:` in compose, since compose doesn't support env-var
  interpolation in that field.
- **Hostname per worktree.** `.devcontainer/init.sh` runs as
  `initializeCommand` on the host and writes
  `.devcontainer/.env` with `WORKTREE_NAME=<basename of worktree>`.
  Compose interpolates that into the dev container service's
  `hostname:` so shell prompts and `docker ps` show readable names.
- **Per-worktree data volumes.** `app-mssql-data`,
  `servicebus-mssql-data`, and `azurite-data` get the compose project
  prefix, so each worktree has independent database and storage state.
  A destructive migration in one worktree doesn't touch the others.
- **Shared Claude config volume.** `claude-code-config` is declared
  `external: true` in compose under the fixed name
  `claude-code-config-shared`. The volume is created idempotently by
  `init.sh` (`docker volume create`) before compose comes up, and
  because it's external, `docker compose down -v` in any worktree
  _won't_ drop it — every worktree's container shares one Claude
  login, memory, and settings.
- **Per-worktree window title.** `.vscode/settings.json` sets
  `window.title` using `${workspaceFolderBasename}`, so VS Code
  windows show `[main]`, `[feat-auth-rework]`, etc.

## Cleanup

```bash
# From the host shell, NOT from inside the worktree you're removing:
cd ~/code/snapsort/main
./scripts/remove-worktree.sh feat/auth-rework
```

This:

1. Discovers the actual compose project name from container labels
   (`devcontainer.local_folder=<worktree>` →
   `com.docker.compose.project=<name>`). Pass `--project <name>` to
   override discovery if the containers were already removed manually.
2. Stops + removes the worktree's compose stack (`docker compose -p
<project> down -v --remove-orphans`).
3. Drops the per-project volumes (DB data, blob/queue/table data).
4. Removes the worktree directory and the git worktree registration.
5. Lists any remaining `<project>_*` volumes for manual review.

The shared `claude-code-config-shared` volume is preserved because it
is declared `external: true` in compose.

## Alternative: Claude Code's built-in worktree isolation

For short-lived sub-agent work — e.g. having an agent investigate a
fix on a throwaway branch within an existing Claude session — you can
use the SDK's worktree isolation directly without creating a full
sibling dev container:

```
Agent({ isolation: "worktree", ... })
```

This creates a temporary worktree, runs the agent in it, and cleans
up automatically (or returns the path/branch if the agent made
changes). Best for one-shot tasks. Use the helper-script flow above
for long-running independent feature work where you want a separate
VS Code window, separate sidecars, and a separate top-level Claude
session.

## Gotchas

- A given branch can only be checked out in one worktree at a time.
  `new-worktree.sh` refuses if the branch is already in another
  worktree.
- Each worktree runs its own SQL Server, Service Bus emulator, and
  Azurite. RAM and disk usage multiply with the number of active
  worktrees — close worktrees you aren't using.
- Each worktree has its own `node_modules/`, `bin/`, and `obj/`.
  These aren't shared — that's intentional (each worktree may build
  against different code), but it costs disk.
- `claude-code-config-shared` is shared, so two Claude instances
  writing settings or memory at the same moment can technically race.
  In practice this rarely causes problems, but be aware.
- Restoring host-side tooling access (SSMS, Azure Storage Explorer)
  to a sidecar requires re-adding a `ports:` mapping on that service.
  See the future work below.

## Future / not yet implemented

- **Env-driven host port mappings for sidecars.** Re-add `ports:` with
  `${VAR:-default}` interpolation, plus an extension to `init.sh` that
  hashes the worktree name into a deterministic per-worktree port
  range. Useful only when host tooling access becomes important.
- **`scripts/list-worktrees.sh`.** A status overview showing each
  worktree alongside its compose project, container state, and any
  allocated host ports.
