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
