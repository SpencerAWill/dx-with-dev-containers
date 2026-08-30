#!/usr/bin/env bash
# Runs on the HOST as `initializeCommand`, before `docker compose up`.
# Two jobs:
#   1. Write WORKTREE_NAME to .devcontainer/.env so compose can
#      interpolate it for the dev container's hostname (readable shell
#      prompts and `docker ps` per worktree).
#   2. Ensure the cross-project Claude config volume exists. It's
#      declared `external: true` in compose so it survives
#      `docker compose down -v` — but external volumes must be
#      pre-created. This makes that idempotent.
#   3. Ensure ~/.config/gh exists on the host, since compose bind-mounts
#      it into the container. Docker would otherwise create a missing
#      bind source as a root-owned directory that the container cannot
#      write to.
#
# Portable across macOS and Linux (no GNU-only flags).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace_dir="$(cd "$script_dir/.." && pwd)"
worktree_name="$(basename "$workspace_dir")"

cat > "$script_dir/.env" <<EOF
WORKTREE_NAME=$worktree_name
EOF

# Idempotent: docker volume create is a no-op if the volume exists.
# Stderr is suppressed so the lifecycle log isn't cluttered on re-runs.
docker volume create claude-code-config-shared >/dev/null 2>&1 || true

# Bind-mount source for the container's gh config. Creating it here keeps
# Docker from inventing it as root. Contents (hosts.yml) come from whatever
# `gh auth login` has stored on the host.
mkdir -p "$HOME/.config/gh"

# The container mounts the PARENT of this directory at /workspaces, because a
# worktree's .git points at <parent>/.bare and git cannot resolve that unless
# the parent comes along (see docker-compose.yml).
#
# In the bare-repo layout that parent holds .bare plus the worktrees, and
# mounting it is exactly right. Before that migration it is merely whatever
# directory happens to contain this checkout, so its other contents are mounted
# too — worth knowing, since anything running in the container can read them.
parent_dir="$(cd "$workspace_dir/.." && pwd)"
if [ ! -d "$parent_dir/.bare" ]; then
  printf '\033[1;33mwarning:\033[0m not in the bare-repo worktree layout yet.\n' >&2
  printf '  The dev container will mount %s at /workspaces,\n' "$parent_dir" >&2
  printf '  so everything alongside this checkout is visible inside it.\n' >&2
  printf '  Run scripts/migrate-to-bare-layout.sh to finish the migration;\n' >&2
  printf '  see docs/devcontainer-worktrees.md.\n' >&2
fi
