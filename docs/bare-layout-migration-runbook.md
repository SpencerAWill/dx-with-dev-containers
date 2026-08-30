# Runbook: migrating to the bare-repo worktree layout

A one-time, host-side procedure that converts a normal checkout into the
bare-repo + sibling-worktrees layout, so several worktrees can each run their own
dev container and sidecar services at once.

Run it with the dev container **stopped**. Most of these commands are on the
host; the few that are not are marked.

Background on the layout itself is in
[devcontainer-worktrees.md](devcontainer-worktrees.md).

---

## Before you start

| Requirement           | Why                                                                                                      |
| --------------------- | -------------------------------------------------------------------------------------------------------- |
| Everything pushed     | The new layout is built by cloning from `origin`. Unpushed commits and stashes do not come across.       |
| git 2.48 or newer     | `worktree add --relative-paths` is what lets the same worktree resolve on the host and in the container. |
| Clean working tree    | The migration script refuses otherwise.                                                                  |
| `code` on your PATH   | VS Code: `Cmd+Shift+P` → _Shell Command: Install 'code' command in PATH_.                                |
| Dev container stopped | Rebinding paths under a live bind mount confuses Docker.                                                 |

The script checks the first three and refuses rather than half-finishing.

**Untracked files do not survive**, because the new tree is a fresh clone —
`apps/mobile/.env` and any local `appsettings` overrides among them. Step 6
copies back the one that usually matters; the rest stay in the backup directory
until you delete it in step 12.

---

## Migrate

**1. Push, then stop the container.** In VS Code: `Cmd+Shift+P` →
_Dev Containers: Close Remote Connection_, or quit VS Code.

```sh
git push
docker ps          # expect no snapsort containers
```

**2. Go to the checkout and capture where it lives.** Every later step uses
these two variables, so run this in the shell you will keep using.

```sh
cd /path/to/dx-with-dev-containers      # ← your actual path
PARENT="$(dirname "$PWD")"
NAME="$(basename "$PWD")"
git --version                            # must be 2.48+
```

**3. Optional: drop the old stack's volumes.** After migrating, VS Code derives
a new Compose project name from the new path, so the old project's containers
and volumes are orphaned. This deletes the local demo database; migrations
recreate it on next start.

```sh
docker compose ls -a
docker compose -p <old-project-name> down -v
```

**4. Dry run, then migrate.** The dry run changes nothing and prints the plan.

```sh
./scripts/migrate-to-bare-layout.sh
./scripts/migrate-to-bare-layout.sh --confirm
```

This builds `$PARENT/$NAME-bare-layout/` beside the checkout. Your existing
checkout is untouched at this point.

**5. Swap the layouts.** The script prints these with your real paths.

```sh
cd "$PARENT"
mv "$NAME" "$NAME.pre-bare-backup"
mv "$NAME-bare-layout" "$NAME"
```

**6. Carry over untracked files.**

```sh
cp "$NAME.pre-bare-backup/apps/mobile/.env" "$NAME/main/apps/mobile/.env" 2>/dev/null || true
```

**7. Open the worktree**, then _Reopen in Container_. The first build is from
scratch and `postCreate` runs restore, `pnpm install` and EF migrations, so
expect a few minutes.

```sh
code "$PARENT/$NAME/main"
```

---

## Verify

**8. Inside the container** — this is the moment of truth for the workspace
mount. If the mount were wrong, `git status` would fail here.

```sh
git status                    # must NOT say "not a git repository"
cat .git                      # gitdir: ../.bare/worktrees/main   (relative, not absolute)
git status -sb | head -1      # ## main...origin/main             (upstream tracking present)
pwd                           # /workspaces/main
./scripts/check-worktree-isolation.sh
```

All ten static checks should pass. The live pass reports itself skipped inside
the container, which is expected — it needs the docker CLI.

---

## Prove parallelism

The live pass has never run against two real stacks. This is what exercises it.

**9. Create a second worktree** (host, from the `main` worktree):

```sh
cd "$PARENT/$NAME/main"
./scripts/new-worktree.sh test/parallel
code "$PARENT/$NAME/test-parallel"      # then Reopen in Container
```

**10. With both containers up, run the check on the host:**

```sh
cd "$PARENT/$NAME/main"
./scripts/check-worktree-isolation.sh
```

Expect: two Compose projects, no published host ports, one network per project,
and `claude-code-config-shared` existing once rather than once per worktree.

**11. Tear the test worktree down** — not from inside it:

```sh
cd "$PARENT/$NAME/main"
./scripts/remove-worktree.sh test/parallel
```

**12. Once everything works, delete the backup.**

```sh
rm -rf "$PARENT/$NAME.pre-bare-backup"
```

---

## Rollback

Nothing is destroyed until step 12, so until then rollback is a rename:

```sh
cd "$PARENT"
mv "$NAME" "$NAME.bare-layout-failed"
mv "$NAME.pre-bare-backup" "$NAME"
code "$NAME"                             # Reopen in Container
```

The only thing that does not come back on its own is the old Compose project's
volumes, if you removed them in step 3 — the database rebuilds from migrations.

---

## Troubleshooting

**`fatal: not a git repository` inside the container.** The workspace mount is
not reaching `.bare`, or the worktree was created with absolute paths. Check
that `docker-compose.yml` mounts `../..:/workspaces` and that `cat .git` shows a
_relative_ gitdir. A worktree created without `--relative-paths` has to be
recreated; `git worktree repair` rewrites paths but keeps them absolute.

**The migration script says git is too old.** It needs 2.48+ for
`--relative-paths`. On macOS, `brew install git` and make sure the Homebrew git
comes first on your PATH — the system git is older.

**`docker compose -p <name> down -v` complains about a missing compose file.**
Some Docker versions want the file even with `-p`. Point at it explicitly:

```sh
docker compose -f "$PARENT/$NAME/main/.devcontainer/docker-compose.yml" -p <name> down -v
```

**`gh` is not authenticated in the new container.** The container inherits the
host's login through a bind mount of `~/.config/gh`, and on macOS that only
carries a token if it is in `hosts.yml` rather than the Keychain. Run
`gh auth login --insecure-storage` on the host once.

**The container warns it is "not in the bare-repo worktree layout yet".** That
is `init.sh` telling you the mount is pulling in the parent directory of an
unmigrated checkout. It disappears once step 5 is done.

**A branch you asked for already exists on origin.** `new-worktree.sh` checks
`refs/remotes/origin/<branch>` and tracks it. If you see a brand-new branch off
HEAD instead, you are on an older copy of the script.
