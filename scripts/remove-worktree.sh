#!/usr/bin/env bash
# Tear down a worktree's dev container stack and remove the worktree.
#
# Run from the HOST shell. Discovers the actual compose project name by
# looking at the labels VS Code's dev containers extension wrote on the
# containers, then runs `docker compose -p <project> down -v` to remove
# them along with per-project volumes. The shared
# claude-code-config-shared volume is declared `external` in compose so
# it is *not* dropped here.
#
# Usage:
#   scripts/remove-worktree.sh <branch>
#   scripts/remove-worktree.sh <branch> --project <name>   # override discovery
set -euo pipefail

bold=$'\033[1m'
red=$'\033[1;31m'
yellow=$'\033[1;33m'
green=$'\033[1;32m'
cyan=$'\033[1;36m'
reset=$'\033[0m'

die() { echo "${red}error:${reset} $*" >&2; exit 1; }
note() { echo "${cyan}==>${reset} $*"; }
warn() { echo "${yellow}warning:${reset} $*" >&2; }

[ $# -ge 1 ] || die "usage: $(basename "$0") <branch> [--project <name>]"
branch="$1"; shift
project_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project) project_override="${2:-}"; shift 2 || die "--project requires a name" ;;
    *) die "unknown argument: $1" ;;
  esac
done

git_common="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || die "not inside a git repository"
git_common="$(cd "$git_common" && pwd)"
[ "$(basename "$git_common")" = ".bare" ] \
  || die "not in bare-repo layout"

parent="$(dirname "$git_common")"

# Find the worktree path for this branch.
worktree=""
current_path=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) current_path="${line#worktree }" ;;
    "branch refs/heads/$branch") worktree="$current_path" ;;
  esac
done < <(git -C "$parent" worktree list --porcelain)

[ -n "$worktree" ] || die "no worktree found for branch '$branch'"

cwd="$(pwd -P)"
case "$cwd/" in
  "$worktree"/*) die "refuse to remove worktree from inside it (cd elsewhere first)" ;;
esac

# Resolve the compose project name. VS Code dev containers labels each
# container with `devcontainer.local_folder=<host-path-to-worktree>` and
# compose labels them with `com.docker.compose.project=<project-name>`.
# We use the first to find containers, the second to read the project.
project="$project_override"
if [ -z "$project" ]; then
  project="$(
    docker container ls -a \
      --filter "label=devcontainer.local_folder=$worktree" \
      --format '{{ index .Labels "com.docker.compose.project" }}' \
      2>/dev/null \
      | awk 'NF { print; exit }'
  )"
fi

if [ -n "$project" ]; then
  note "tearing down compose project ${bold}$project${reset}"
  docker compose -p "$project" down -v --remove-orphans
else
  warn "could not auto-discover the compose project for $worktree"
  warn "(no containers with label devcontainer.local_folder=$worktree found)"
  warn "if there are stale containers/volumes, rerun with --project <name>"
fi

note "removing git worktree at $worktree"
git -C "$parent" worktree remove "$worktree"

if [ -n "$project" ]; then
  echo ""
  echo "Any remaining docker volumes prefixed ${bold}${project}_${reset} (review before deleting):"
  docker volume ls --format '{{.Name}}' | grep "^${project}_" || echo "  (none)"
fi

echo ""
echo "${green}Done.${reset}"
