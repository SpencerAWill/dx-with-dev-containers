#!/usr/bin/env bash
# One-time conversion from a regular checkout to bare-repo + sibling-
# worktrees layout, so this directory becomes a parent that holds many
# worktrees at once.
#
# Run from the HOST shell, from inside the existing checkout. The script
# is non-destructive: it builds the new layout in a sibling staging
# directory and prints rename instructions for you to apply manually
# after verifying. Make sure the dev container is stopped first
# (rebinding paths under a running bind mount confuses Docker).
#
# Usage: scripts/migrate-to-bare-layout.sh [--confirm]
#
# Without --confirm, the script does a dry-run: prereq checks + a
# preview of what it would do, no filesystem changes.
#
# Result layout (in the staging directory):
#   <parent>/<repo>-bare-layout/
#     ├── .bare/              bare clone of origin
#     ├── .git                pointer file: "gitdir: ./.bare"
#     └── <current-branch>/   worktree for the branch you were on
set -euo pipefail

bold=$'\033[1m'
red=$'\033[1;31m'
yellow=$'\033[1;33m'
green=$'\033[1;32m'
cyan=$'\033[1;36m'
reset=$'\033[0m'

die() { echo "${red}error:${reset} $*" >&2; exit 1; }
note() { echo "${cyan}==>${reset} $*"; }

confirm=0
case "${1:-}" in
  --confirm) confirm=1 ;;
  "") ;;
  *) die "unknown argument: $1" ;;
esac

# Move to the repo top level so subsequent relative-path logic is stable.
top="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git repository"
cd "$top"

# Refuse if already in a bare-repo layout (`.git` is a file, not a dir).
[ -d ".git" ] || die "this looks like a worktree (.git is not a directory). Already migrated?"

# The new worktree is created with relative paths so the same metadata resolves
# on the host and at /workspaces/<name> in the container. Added in git 2.48.
#
# Compared field by field rather than with `sort -V`, which is a GNU extension
# this script cannot count on — it runs on the host, and macOS ships BSD sort.
git_version="$(git --version | awk '{print $3}')"
git_major="${git_version%%.*}"
git_rest="${git_version#*.}"
git_minor="${git_rest%%.*}"
if [ "$git_major" -lt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -lt 48 ]; }; then
  die "git $git_version is too old — 2.48+ is needed for 'worktree add --relative-paths',
       without which the container cannot resolve the worktree's git directory"
fi

# Sanity: clean tree, pushed work.
if [ -n "$(git status --porcelain)" ]; then
  die "working tree is not clean — commit or stash, then rerun"
fi

# The new layout is built by cloning from the remote, so anything that exists
# only locally does not survive it. Checking just the current branch would miss
# most of that, so check every local branch and the stash.
unpushed=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if ! git rev-parse --verify --quiet "$ref@{u}" >/dev/null 2>&1; then
    unpushed="$unpushed  $ref (no upstream — exists only here)"$'\n'
  elif [ -n "$(git log "$ref@{u}..$ref" --oneline 2>/dev/null)" ]; then
    unpushed="$unpushed  $ref (has unpushed commits)"$'\n'
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

if [ -n "$(git stash list 2>/dev/null)" ]; then
  unpushed="$unpushed  (you also have stashed changes, which are not cloned)"$'\n'
fi

if [ -n "$unpushed" ]; then
  echo "${yellow}warning:${reset} work that a fresh clone would not carry over:"
  printf '%s' "$unpushed"
  die "push or back it up before migrating (--confirm will not bypass this)"
fi

remote_url="$(git config --get remote.origin.url)" \
  || die "no remote.origin.url configured — migration needs a remote to clone --bare from"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
checkout_path="$top"
parent="$(dirname "$checkout_path")"
repo_name="$(basename "$checkout_path")"
staging="$parent/${repo_name}-bare-layout"

cat <<EOF
Migration plan:
  ${bold}From${reset}: $checkout_path  (regular checkout on branch $current_branch)
  ${bold}To${reset}  : $staging         (bare-repo + sibling-worktrees, staging)
  ${bold}Remote${reset}: $remote_url

Steps that will run:
  1. mkdir $staging
  2. git clone --bare $remote_url $staging/.bare
  3. configure origin fetch refspec on the bare repo
  4. echo 'gitdir: ./.bare' > $staging/.git
  5. git -C $staging worktree add --relative-paths $current_branch $current_branch
  6. set upstream tracking on the new worktree
  7. (you) mv $checkout_path ${checkout_path}.pre-bare-backup
  8. (you) mv $staging $checkout_path
  9. (you) verify, then rm -rf ${checkout_path}.pre-bare-backup

${yellow}Note${reset}: the new layout is built by cloning from the remote, so files git
does not track do not come across — ${bold}apps/mobile/.env${reset} and any local
appsettings overrides among them. They stay in the backup directory from
step 7 until you delete it.

EOF

if [ "$confirm" -ne 1 ]; then
  echo "${yellow}Dry run.${reset} Re-run with ${bold}--confirm${reset} to perform steps 1-6."
  echo "(Steps 7-9 are always manual so you can verify before deleting anything.)"
  exit 0
fi

[ ! -e "$staging" ] || die "staging directory already exists: $staging"

note "creating staging directory $staging"
mkdir "$staging"

note "cloning --bare from $remote_url into $staging/.bare"
git clone --bare "$remote_url" "$staging/.bare"

note "configuring origin fetch refspec so worktree branch tracking works"
git -C "$staging/.bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$staging/.bare" fetch origin

note "writing .git pointer file"
echo "gitdir: ./.bare" > "$staging/.git"

# --relative-paths writes "gitdir: ../.bare/worktrees/<name>" instead of a host
# absolute path. The container mounts the parent at /workspaces, so an absolute
# host path would not exist in there and every git command would fail.
note "creating worktree for current branch $current_branch"
git -C "$staging" worktree add --relative-paths "$current_branch" "$current_branch"

# `git clone --bare` copies refs/heads/* but writes no branch.<name>.remote or
# .merge, so the new worktree would have no upstream: no ahead/behind in
# `git status`, and `git push` failing with "no upstream branch".
note "setting upstream tracking for $current_branch"
git -C "$staging/$current_branch" branch \
  --set-upstream-to "origin/$current_branch" "$current_branch" >/dev/null

cat <<EOF

${green}Staging complete.${reset}

Now, with the dev container stopped, swap layouts manually:

  ${bold}mv $checkout_path ${checkout_path}.pre-bare-backup${reset}
  ${bold}mv $staging $checkout_path${reset}

Then open the worktree in VS Code and Reopen in Container:

  ${bold}code $checkout_path/$current_branch${reset}

After verifying everything works, you can delete the backup:

  ${bold}rm -rf ${checkout_path}.pre-bare-backup${reset}
EOF
