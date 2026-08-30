#!/usr/bin/env bash
# Runs INSIDE the container, from postCreateCommand, with the workspace folder
# as the working directory.
#
# Everything here exists because the repository is bind-mounted from the host
# and may be a git worktree, which is a combination git needs help with.
set -euo pipefail

workspace="$(pwd)"

# git config --global --add appends unconditionally, so adding the same path on
# every rebuild would grow the list forever.
trust() {
  local path="$1"
  [ -n "$path" ] || return 0
  if ! git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$path"; then
    git config --global --add safe.directory "$path"
  fi
}

# A bind-mounted repository often appears owned by a different uid than the
# container user, and git refuses to touch a repo it thinks someone else owns.
# Trusting these two paths specifically is preferable to safe.directory=*.
trust "$workspace"

# In the bare-repo layout the real git directory is .bare, a sibling of the
# worktree rather than a directory inside it, so it needs trusting separately.
# Resolvable only after the workspace itself is trusted, hence the order.
common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$common" ]; then
  common="$(cd "$common" 2>/dev/null && pwd || true)"
  trust "$common"
fi

# Worktree metadata is written by the host, at host paths, and read in here at
# container paths — /workspaces/<name> rather than /Users/you/code/repo/<name>.
# Relative paths are the only form valid on both sides. The host-side scripts
# pass --relative-paths when creating a worktree; this covers any created from
# inside the container.
git config --global worktree.useRelativePaths true

# Several containers share one .bare in this layout. Background gc firing in one
# of them would be repacking a repository the others are actively using.
git config --global gc.auto 0
