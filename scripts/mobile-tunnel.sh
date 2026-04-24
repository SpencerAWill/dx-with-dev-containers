#!/usr/bin/env bash
# Bring up the mobile demo end-to-end:
#   1. Start a cloudflared quick tunnel pointing at web-api:5000
#   2. Wait for its public https URL
#   3. Write that URL into apps/mobile/.env as EXPO_PUBLIC_API_URL
#   4. Start Expo in tunnel mode so Expo Go on a phone can load Metro
# When pnpm tunnel exits (Ctrl+C), cloudflared is cleaned up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOBILE_DIR="$REPO_ROOT/apps/mobile"
ENV_FILE="$MOBILE_DIR/.env"
API_PORT="${API_PORT:-5000}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "error: cloudflared is not installed. Rebuild the dev container." >&2
  exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "error: pnpm is not installed." >&2
  exit 1
fi

LOG="$(mktemp)"
cleanup() {
  if [[ -n "${CF_PID:-}" ]] && kill -0 "$CF_PID" 2>/dev/null; then
    kill "$CF_PID" 2>/dev/null || true
  fi
  rm -f "$LOG"
}
trap cleanup EXIT INT TERM

echo "→ starting cloudflared quick tunnel to http://localhost:${API_PORT}"
cloudflared tunnel --url "http://localhost:${API_PORT}" >"$LOG" 2>&1 &
CF_PID=$!

API_URL=""
for _ in $(seq 1 30); do
  if ! kill -0 "$CF_PID" 2>/dev/null; then
    echo "error: cloudflared exited before reporting a URL. Output:" >&2
    cat "$LOG" >&2
    exit 1
  fi
  API_URL="$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$LOG" | head -n1 || true)"
  [[ -n "$API_URL" ]] && break
  sleep 1
done

if [[ -z "$API_URL" ]]; then
  echo "error: timed out waiting for trycloudflare URL. Output:" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "→ api tunnel:  $API_URL"

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

echo "→ starting Expo in tunnel mode (scan the QR with Expo Go)"
cd "$MOBILE_DIR"
pnpm tunnel
