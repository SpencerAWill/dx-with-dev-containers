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

# Identity. Arrives as environment variables on the compose service; init.sh
# reads the resolved values from the host's git and writes them to
# .devcontainer/.env. Applying them here rather than relying on VS Code's
# `dev.containers.copyGitConfig` means the container gets an author regardless
# of how any individual's editor is configured — and regardless of whether the
# host keeps its identity in ~/.gitconfig, in XDG, or behind an includeIf.
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# Worth failing loudly here rather than at the first commit: git's own error
# ("unable to auto-detect email address") points at --global as the fix, which
# is the wrong layer — the value belongs on the host, so it survives a rebuild.
if [ -z "$(git config --get user.email || true)" ]; then
  printf '\033[1;33mwarning:\033[0m git has no user.email; commits will fail.\n' >&2
  printf '  Set it on the HOST and rebuild the container:\n' >&2
  printf '    git config --global user.email "you@example.com"\n' >&2
fi
