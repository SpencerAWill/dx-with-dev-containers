#!/usr/bin/env bash
# Create a sibling git worktree for parallel dev container use.
#
# Run this from the HOST shell (not inside the dev container) — the bare
# repo and sibling worktrees live on the host filesystem and aren't
# visible inside the bind-mounted container.
#
# Usage: scripts/new-worktree.sh <branch> [base-branch]
#
# Layout assumed (created by scripts/migrate-to-bare-layout.sh):
#   <parent>/.bare/           bare git repo
#   <parent>/.git             pointer file: "gitdir: ./.bare"
#   <parent>/<worktree>/      one directory per worktree
set -euo pipefail

bold=$'\033[1m'
red=$'\033[1;31m'
green=$'\033[1;32m'
cyan=$'\033[1;36m'
reset=$'\033[0m'

die() { echo "${red}error:${reset} $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: $(basename "$0") <branch> [base-branch]"
branch="$1"
base="${2:-}"

# Verify bare-repo layout. `git rev-parse --git-common-dir` resolves to
# the bare repo's path from any worktree; checking its basename is .bare
# tells us we're in the layout this script supports.
git_common="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || die "not inside a git repository"
git_common="$(cd "$git_common" && pwd)"
[ "$(basename "$git_common")" = ".bare" ] \
  || die "not in bare-repo layout — run scripts/migrate-to-bare-layout.sh first"

parent="$(dirname "$git_common")"

# Slugify branch name for the directory (refs allow `/`, paths shouldn't).
slug="${branch//\//-}"
target="$parent/$slug"

[ ! -e "$target" ] || die "path already exists: $target"

# Refuse if the branch is already checked out in another worktree.
if git -C "$parent" worktree list --porcelain | grep -q "^branch refs/heads/$branch\$"; then
  die "branch '$branch' is already checked out in another worktree"
fi

# --relative-paths writes "gitdir: ../.bare/worktrees/<name>" into the new
# worktree instead of a host absolute path. The dev container mounts the parent
# at /workspaces, where a host path like /Users/you/code/repo would not exist,
# so an absolute one leaves git broken inside the container.
if git -C "$parent" show-ref --verify --quiet "refs/heads/$branch"; then
  echo "${cyan}==>${reset} adding worktree for existing branch ${bold}$branch${reset} at $target"
  git -C "$parent" worktree add --relative-paths "$target" "$branch"

elif git -C "$parent" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  # The branch exists on the remote but not locally. Without this case the
  # script would fall through to the else and quietly create an unrelated new
  # branch from HEAD, sharing only a name with the one on origin.
  echo "${cyan}==>${reset} checking out remote branch ${bold}origin/$branch${reset} at $target"
  git -C "$parent" worktree add --relative-paths --track \
    -b "$branch" "$target" "origin/$branch"

else
  base_ref="${base:-HEAD}"
  echo "${cyan}==>${reset} creating new branch ${bold}$branch${reset} from ${bold}$base_ref${reset} at $target"
  git -C "$parent" worktree add --relative-paths -b "$branch" "$target" "$base_ref"
  echo "    (new branch — push with ${bold}git push -u origin $branch${reset})"
fi

echo ""
echo "${green}Worktree ready.${reset} Next steps (on the host):"
echo ""
echo "  ${bold}code $target${reset}"
echo "  → then: ${bold}Dev Containers: Reopen in Container${reset}"
echo ""
echo "Or, from a host terminal:"
echo "  ${bold}cd $target${reset} && ${bold}claude${reset}"
echo ""
