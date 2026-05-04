# Migrate this repo's dev container setup to support parallel worktree development

I want to be able to run multiple instances of this repo simultaneously — each
in its own git worktree, each in its own dev container, each with its own
sidecar services — without port conflicts, volume collisions, or shared-state
corruption. The end goal is being able to run multiple Claude Code agents in
parallel, each on a different branch, each in a fully isolated environment.

This is a phased migration. **Do not skip ahead.** At the end of each phase,
stop and report what you found / changed, and wait for me to confirm before
continuing. Each phase should leave the repo in a working state.

---

## Phase 1 — Audit (read-only, no changes)

Inspect the current setup and produce a written report covering:

**Container identity**

- Contents of `.devcontainer/devcontainer.json` (or wherever the dev container
  config lives — check `.devcontainer/`, root, and any subfolders).
- Whether `runArgs` includes a hardcoded `--name` or `--hostname`.
- Whether there's a `name` field in `devcontainer.json` and whether it's static.

**Compose (if present)**

- Whether a `docker-compose.yml` / `compose.yml` is referenced from the dev
  container config.
- Whether the compose file has an explicit top-level `name:` field.
- For each service: whether it has a `ports:` section, and whether the
  mappings are hardcoded host ports (`"5432:5432"`) or container-only.

**Ports**

- Everything in `forwardPorts` and `appPort`.
- Any `portsAttributes` configuration.

**Mounts and volumes**

- Every entry in `mounts`, classified as: bind mount (host path), named volume
  (shared name), or named volume (per-instance name).
- Any named volumes declared in the compose file and whether their names are
  static or interpolated.

**Connection strings and host references**

- Run `git grep -nE "(localhost|127\.0\.0\.1):[0-9]+" -- ':!*.md' ':!*.lock' ':!*.sum'`
  and report results.
- Identify which matches are inside code that runs _inside_ the container
  (problematic — should use service hostnames) vs host-side tooling (fine).
- Check appsettings\*.json, .env files, and any config templates for hardcoded
  hostnames.

**External dependencies**

- Any seed scripts, migrations, or startup hooks that assume specific host
  ports or shared external resources.
- Any reference to shared dev databases, shared S3 buckets, etc.

**Output:** A markdown report with one section per category above, ending with
a bulleted list titled "Things that will break with two concurrent instances"
that maps audit findings to specific risks. Do not propose fixes yet.

**STOP. Wait for me to review the audit before proceeding.**

---

## Phase 2 — Make the existing single-instance setup parallel-safe

Based on the audit, modify the dev container config so that _if_ two instances
were run simultaneously they wouldn't collide. We are still only running one
instance during this phase — the goal is to fix the config without changing
the workflow yet.

Required changes (apply only those relevant based on the audit):

1. **Container/project naming.** Replace any hardcoded container name with
   `${localWorkspaceFolderBasename}`-derived names in `runArgs`. If using
   compose, add `name: <repo>-${WORKTREE_NAME:-default}` at the top of the
   compose file.

2. **Sidecar ports.** Remove `ports:` mappings from compose services that are
   only consumed by other services on the internal network (db, redis, kafka,
   etc.). Verify the app uses service hostnames, not `localhost`, to reach
   them. For sidecars that genuinely need host access, convert to env-driven:
   `"${DB_HOST_PORT:-5432}:5432"`.

3. **App ports.** Keep entries in `forwardPorts` but remove any hardcoded
   host-side port pinning. Add `portsAttributes` with `onAutoForward: "notify"`
   so VS Code allocates free host ports and surfaces them.

4. **Volumes.** Convert any named volumes that should be per-instance (e.g.
   `node_modules`, package caches, sidecar data volumes) to use
   `${localWorkspaceFolderBasename}` in their names. Leave anything that
   should be shared (e.g. shared auth tokens) with a static name.

5. **Connection strings.** Fix any in-container code that hardcodes
   `localhost:<port>` for sidecar access — replace with the service hostname.

After changes:

- Run "Dev Containers: Rebuild Container" mentally (i.e., describe the rebuild
  command for me to run; you can't trigger it yourself).
- List exactly which files you modified and a one-line summary of each change.
- Flag anything you were uncertain about and chose not to change.

**STOP. I will rebuild the container and verify the single-instance setup
still works normally before we proceed.**

---

## Phase 3 — Document the parallel-safety verification procedure

Don't make any code changes in this phase. Instead, produce a short markdown
document at `docs/devcontainer-parallel-verification.md` that walks me through
verifying parallel-safety using a second clone (not a worktree yet — that's
the next phase). The doc should include:

- The exact `git clone` and `code <path>` commands to run.
- A checklist of things to verify once both containers are up: distinct
  container names in `docker ps`, distinct host ports in each VS Code Ports
  panel, separate volumes in `docker volume ls`, isolated sidecar state.
- A teardown procedure that includes `docker compose -p <project> down -v`
  and removing the test clone directory.

**STOP. I will follow the doc and confirm parallel-from-clones works before
we move on.**

---

## Phase 4 — Add worktree support

Now make the changes that turn this from "parallel-safe" into "worktree-native."

1. **`initializeCommand` for env generation.** Add an `initializeCommand` to
   `devcontainer.json` that runs a script to generate `.devcontainer/.env`
   containing at minimum `WORKTREE_NAME=<basename>`. If the audit identified
   sidecars that need host-port access, also generate deterministic per-
   worktree ports (hash the worktree name into a port range, e.g.
   15000–15999 for db, 16000–16999 for redis).

2. **The script itself.** Place it at `scripts/devcontainer-init.sh`, make it
   executable, and write it portably (bash, no GNU-specific flags — it needs
   to work on macOS and Linux). Add `.devcontainer/.env` to `.gitignore`.

3. **Helper scripts.** Create:
   - `scripts/new-worktree.sh <branch> [base-branch]` — creates a worktree as
     a sibling directory and opens it in VS Code with a printed reminder to
     "Reopen in Container."
   - `scripts/remove-worktree.sh <branch>` — runs `git worktree remove`,
     `docker compose -p <project> down -v`, and `docker volume rm` for any
     per-worktree volumes matching the pattern.
     Both should be defensive: check the worktree exists / doesn't exist as
     appropriate, refuse to remove the current worktree, etc.

4. **Update the compose file** to read from `.env` for the project name and
   any port variables, with sensible defaults so the file still works if
   someone runs it outside the worktree workflow.

5. **Documentation.** Update or create `docs/devcontainer-worktrees.md`
   covering: how to create a new worktree, how the env generation works, how
   to clean up, and the gotchas (branch checkout collision, resource usage,
   per-worktree node_modules, etc.).

**STOP. I will create a test worktree from a throwaway branch, open it in a
container, verify both the original checkout and the worktree can run
simultaneously, and confirm the cleanup script works.**

---

## Phase 5 — Polish (only if I confirm I want it)

Wait for me to explicitly request this phase. Possible additions:

- Per-worktree window title via `.vscode/settings.json`.
- A `scripts/list-worktrees.sh` that shows worktrees alongside their
  container status and allocated ports.
- README updates pointing to the new docs.
- Suggesting library/tool additions (e.g. GitLens worktree view, Orbstack on
  macOS, git-worktree-switcher) — as suggestions, not installations.

---

## Constraints throughout

- **Don't restructure the repo into the bare-repo + sibling-worktrees layout.**
  Keep the existing checkout in place; add worktrees as siblings. The bare-repo
  conversion is a separate decision I'll make later.
- **Preserve existing behavior.** Anything that works today must still work
  after each phase. If a change risks breaking something, flag it and ask.
- **Follow this repo's existing conventions** for shell scripts, config file
  style, documentation location, and commit message format. If conventions
  aren't clear, ask before guessing.
- **Comment non-obvious logic** in the helper scripts — especially the port-
  hashing function and any platform-specific bash.
- **Don't commit anything.** Stage changes if helpful, but leave commits to me
  so I can review and group them sensibly.
- **If you find an existing partial implementation** (e.g. a half-finished
  init script, an unused env var), surface it during the audit rather than
  silently working around it.
