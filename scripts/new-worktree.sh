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

if git -C "$parent" show-ref --verify --quiet "refs/heads/$branch"; then
  echo "${cyan}==>${reset} adding worktree for existing branch ${bold}$branch${reset} at $target"
  git -C "$parent" worktree add "$target" "$branch"
else
  base_ref="${base:-HEAD}"
  echo "${cyan}==>${reset} creating new branch ${bold}$branch${reset} from ${bold}$base_ref${reset} at $target"
  git -C "$parent" worktree add -b "$branch" "$target" "$base_ref"
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
