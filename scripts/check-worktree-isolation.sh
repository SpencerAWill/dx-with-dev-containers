#!/usr/bin/env bash
# Verify that two worktrees can run their full stacks at the same time.
#
# The claim this repo makes — every worktree gets its own dev container and its
# own sidecar services — rests on a handful of invariants that are easy to break
# with a one-line edit. This asserts them instead of trusting them.
#
# Two passes:
#
#   static  Reads the config. Runs anywhere, including inside the dev container,
#           and needs nothing but a shell. This is the pass that catches the
#           regression, because the invariants are all visible in the files.
#
#   live    Inspects running Docker state to confirm two stacks are genuinely
#           namespaced apart. Needs the docker CLI, so in practice it runs on
#           the HOST, not inside the container. Skipped automatically when
#           docker is unavailable.
#
# Usage:
#   scripts/check-worktree-isolation.sh            # static, plus live if docker is present
#   scripts/check-worktree-isolation.sh --static   # static only
#
# Exit code is non-zero if any invariant is violated, so this works as a
# pre-flight check before a demo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE="$REPO_ROOT/.devcontainer/docker-compose.yml"
DEVCONTAINER="$REPO_ROOT/.devcontainer/devcontainer.json"
INIT="$REPO_ROOT/.devcontainer/init.sh"

# Volumes deliberately shared across every worktree. Anything else must stay
# Compose-prefixed so each worktree gets its own copy.
SHARED_VOLUMES=("claude-code-config")

failures=0
checks=0

pass() { checks=$((checks + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf '  \033[31m✗\033[0m %s\n' "$1"
  [ $# -gt 1 ] && printf '      %s\n' "$2"
}
skip() { printf '  \033[33m–\033[0m %s\n' "$1"; }
head() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- static pass

head "Static — configuration invariants"

# 1. Publishing a host port pins it for the whole machine, so the second
#    worktree to start would collide. Everything must reach the host through
#    the editor's dynamic forwarding instead.
if grep -qE '^[[:space:]]*ports:[[:space:]]*$' "$COMPOSE"; then
  offending="$(grep -nE '^[[:space:]]*ports:[[:space:]]*$' "$COMPOSE" | head -3 | tr '\n' ' ')"
  fail "compose publishes no host ports" "found a ports: key at $offending"
else
  pass "compose publishes no host ports"
fi

# 2. devcontainer.json must not use appPort either — it is a literal
#    `docker run -p`, with the same collision problem.
if grep -qE '"appPort"' "$DEVCONTAINER"; then
  fail "devcontainer.json does not use appPort" "appPort binds fixed host ports"
else
  pass "devcontainer.json does not use appPort"
fi

# 3. The container hostname must vary per worktree, or `docker ps` and the
#    shell prompt become guesswork once several are running.
if grep -qE '^[[:space:]]*hostname:[[:space:]]*\$\{WORKTREE_NAME' "$COMPOSE"; then
  pass "container hostname interpolates WORKTREE_NAME"
else
  fail "container hostname interpolates WORKTREE_NAME" "expected hostname: \${WORKTREE_NAME:-...}"
fi

# 4. ...and something has to supply that variable before compose runs.
if grep -q 'WORKTREE_NAME=' "$INIT"; then
  pass "init.sh writes WORKTREE_NAME for compose"
else
  fail "init.sh writes WORKTREE_NAME for compose"
fi

# 5. Only the deliberately shared volumes may be external. An external volume
#    is NOT Compose-prefixed, so every worktree would write to the same one.
# Comments are skipped explicitly: this file explains the external volume in
# prose that itself contains the string "external: true", which an unanchored
# match happily attributes to whichever volume was declared above it.
external_volumes="$(awk '
  /^volumes:/ { in_vols = 1; next }
  in_vols && /^[^[:space:]]/ { in_vols = 0 }
  !in_vols { next }
  /^[[:space:]]*#/ { next }
  /^  [a-zA-Z0-9_-]+:/ { name = $1; sub(/:$/, "", name) }
  /^[[:space:]]+external:[[:space:]]*true[[:space:]]*$/ { print name }
' "$COMPOSE")"

unexpected=""
for vol in $external_volumes; do
  is_expected=0
  for shared in "${SHARED_VOLUMES[@]}"; do
    [ "$vol" = "$shared" ] && is_expected=1
  done
  [ "$is_expected" -eq 0 ] && unexpected="$unexpected $vol"
done

if [ -n "$unexpected" ]; then
  fail "only intended volumes are shared across worktrees" \
    "unexpected external volume(s):$unexpected — these would be written by every worktree"
else
  pass "only intended volumes are shared across worktrees (${SHARED_VOLUMES[*]})"
fi

# 6. An external volume has to exist before compose can start, and init.sh is
#    what guarantees that.
for shared in "${SHARED_VOLUMES[@]}"; do
  if grep -q 'docker volume create' "$INIT"; then
    pass "init.sh pre-creates the shared volume"
  else
    fail "init.sh pre-creates the shared volume" \
      "external volumes are not auto-created; compose will refuse to start"
  fi
  break
done

# 7. Git inside a container sees a repo whose worktree metadata was written by
#    the host, at host paths. Relative paths are what make the same worktree
#    usable from both sides.
if grep -q 'worktree.useRelativePaths' "$DEVCONTAINER"; then
  pass "git worktree.useRelativePaths is configured"
else
  fail "git worktree.useRelativePaths is configured" \
    "without it, a worktree created on the host has .git paths the container cannot resolve"
fi

# ------------------------------------------------------------------ live pass

if [ "${1:-}" = "--static" ]; then
  head "Live — skipped (--static)"
elif ! command -v docker >/dev/null 2>&1; then
  head "Live — skipped"
  skip "docker CLI not available (expected inside the dev container; run this on the host)"
else
  head "Live — running Docker state"

  # Compose labels every container it creates with its project name. Two
  # worktrees running at once must show up as two distinct projects.
  projects="$(docker ps --filter "label=com.docker.compose.service=devcontainer" \
    --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | sort -u)"
  project_count="$(printf '%s\n' "$projects" | grep -c . || true)"

  if [ "$project_count" -lt 2 ]; then
    skip "only $project_count worktree stack(s) running — start a second to exercise this pass"
  else
    pass "$project_count worktree stacks running: $(echo "$projects" | tr '\n' ' ')"

    # No container from any of these stacks may publish a host port.
    published="$(docker ps --filter "label=com.docker.compose.project" \
      --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E '0\.0\.0\.0:|:::' || true)"
    if [ -n "$published" ]; then
      fail "no stack publishes a host port" "$(echo "$published" | head -3 | tr '\n' ';')"
    else
      pass "no stack publishes a host port"
    fi

    # Each project gets its own network, or the stacks can reach each other's
    # databases by service name — which silently works and is very confusing.
    net_count="$(docker network ls --filter "label=com.docker.compose.project" \
      --format '{{.Name}}' 2>/dev/null | sort -u | grep -c . || true)"
    if [ "$net_count" -ge "$project_count" ]; then
      pass "each stack has its own network ($net_count networks)"
    else
      fail "each stack has its own network" "$net_count networks for $project_count projects"
    fi

    # Data volumes must be per-project. The shared ones are expected to appear
    # exactly once and be attached to every stack.
    for shared in "${SHARED_VOLUMES[@]}"; do
      dupes="$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -c "${shared}-shared$" || true)"
      if [ "$dupes" -le 1 ]; then
        pass "shared volume '${shared}' exists once, not per worktree"
      else
        fail "shared volume '${shared}' exists once" "$dupes copies found"
      fi
    done
  fi
fi

# ---------------------------------------------------------------------- result

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf '\033[32m%s checks passed.\033[0m Worktree isolation holds.\n' "$checks"
  exit 0
else
  printf '\033[31m%s of %s checks failed.\033[0m See docs/devcontainer-worktrees.md.\n' "$failures" "$checks"
  exit 1
fi
