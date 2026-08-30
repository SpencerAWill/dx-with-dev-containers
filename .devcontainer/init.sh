#!/usr/bin/env bash
# Runs on the HOST as `initializeCommand`, before `docker compose up`.
# Three jobs:
#   1. Write .devcontainer/.env for compose to interpolate: WORKTREE_NAME for
#      the dev container's hostname (readable shell prompts and `docker ps`
#      per worktree), and the host's git identity so commits inside the
#      container are attributed correctly.
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

# Git identity for the container. VS Code's `dev.containers.copyGitConfig` is
# a per-machine setting that may simply be off, and even when it is on it copies
# ~/.gitconfig literally — so an identity kept in XDG (~/.config/git/config) or
# reached through an includeIf never arrives. Asking git for the resolved values
# covers all three cases, and asking from inside the worktree picks up any
# repo-conditional identity the host has configured.
git_user_name=""
git_user_email=""
if command -v git >/dev/null 2>&1; then
  git_user_name="$(git -C "$workspace_dir" config --get user.name || true)"
  git_user_email="$(git -C "$workspace_dir" config --get user.email || true)"
fi

if [ -z "$git_user_email" ] || [ -z "$git_user_name" ]; then
  printf '\033[1;33mwarning:\033[0m the host has no git user.name/user.email.\n' >&2
  printf '  Commits inside the dev container will fail until you set them:\n' >&2
  printf '    git config --global user.name "Your Name"\n' >&2
  printf '    git config --global user.email "you@example.com"\n' >&2
fi

cat > "$script_dir/.env" <<EOF
WORKTREE_NAME=$worktree_name
GIT_USER_NAME=$git_user_name
GIT_USER_EMAIL=$git_user_email
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
