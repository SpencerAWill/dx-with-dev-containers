#!/usr/bin/env bash
# Bring up the mobile demo end-to-end. Two servers have to be reachable from
# the phone, so each gets its own cloudflared quick tunnel:
#
#   1. web-api :5000  -> written into apps/mobile/.env as EXPO_PUBLIC_API_URL
#   2. Metro   :8081  -> passed to Expo as EXPO_PACKAGER_PROXY_URL, which
#                        overrides the dev server URL Expo advertises, so Expo
#                        Go fetches the manifest and bundle over the tunnel
#
# Using cloudflared for Metro too means no @expo/ngrok download on first run
# (it is not in the lockfile). Set EXPO_TUNNEL=ngrok to use Expo's own tunnel
# for Metro instead.
#
# Both tunnels are cleaned up when Expo exits (Ctrl+C).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOBILE_DIR="$REPO_ROOT/apps/mobile"
ENV_FILE="$MOBILE_DIR/.env"
API_PORT="${API_PORT:-5000}"
METRO_PORT="${METRO_PORT:-8081}"
EXPO_TUNNEL="${EXPO_TUNNEL:-cloudflared}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "error: cloudflared is not installed. Rebuild the dev container." >&2
  exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "error: pnpm is not installed." >&2
  exit 1
fi

TUNNEL_PIDS=()
LOGS=()
cleanup() {
  for pid in "${TUNNEL_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null || true
  done
  for log in "${LOGS[@]:-}"; do
    [[ -n "$log" ]] && rm -f "$log"
  done
}
trap cleanup EXIT INT TERM

# start_tunnel <local-port> — sets TUNNEL_URL.
#
# Deliberately not `url=$(start_tunnel ...)`: command substitution runs the
# function in a subshell, so the TUNNEL_PIDS/LOGS appends would be lost and
# cleanup would leave the tunnels running after exit.
start_tunnel() {
  local port="$1" log url=""
  log="$(mktemp)"
  LOGS+=("$log")

  cloudflared tunnel --url "http://localhost:${port}" >"$log" 2>&1 &
  local pid=$!
  TUNNEL_PIDS+=("$pid")

  for _ in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "error: cloudflared for port ${port} exited before reporting a URL. Output:" >&2
      cat "$log" >&2
      return 1
    fi
    url="$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$log" | head -n1 || true)"
    [[ -n "$url" ]] && break
    sleep 1
  done

  if [[ -z "$url" ]]; then
    echo "error: timed out waiting for a trycloudflare URL for port ${port}. Output:" >&2
    cat "$log" >&2
    return 1
  fi

  TUNNEL_URL="$url"
}

echo "→ starting cloudflared quick tunnel to http://localhost:${API_PORT} (api)"
start_tunnel "$API_PORT"
API_URL="$TUNNEL_URL"
echo "→ api tunnel:    $API_URL"

mkdir -p "$MOBILE_DIR"
touch "$ENV_FILE"
if grep -q '^EXPO_PUBLIC_API_URL=' "$ENV_FILE"; then
  # Replace the existing line (portable sed — no -i differences between GNU/BSD)
  TMP="$(mktemp)"
  grep -v '^EXPO_PUBLIC_API_URL=' "$ENV_FILE" >"$TMP" || true
  echo "EXPO_PUBLIC_API_URL=$API_URL" >>"$TMP"
  mv "$TMP" "$ENV_FILE"
else
  echo "EXPO_PUBLIC_API_URL=$API_URL" >>"$ENV_FILE"
fi
echo "→ wrote EXPO_PUBLIC_API_URL to apps/mobile/.env"

cd "$MOBILE_DIR"

if [[ "$EXPO_TUNNEL" == "ngrok" ]]; then
  echo "→ starting Expo in ngrok tunnel mode (scan the QR with Expo Go)"
  exec pnpm tunnel
fi

echo "→ starting cloudflared quick tunnel to http://localhost:${METRO_PORT} (metro)"
start_tunnel "$METRO_PORT"
METRO_URL="$TUNNEL_URL"
echo "→ metro tunnel:  $METRO_URL"

echo "→ starting Expo (scan the QR with Expo Go)"
export EXPO_PACKAGER_PROXY_URL="$METRO_URL"
exec pnpm start --port "$METRO_PORT"
