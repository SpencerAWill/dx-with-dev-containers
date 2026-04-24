# SnapSort Mobile (Expo)

Expo Router app that lists and uploads images against the SnapSort API.

## First run

```bash
cd apps/mobile
pnpm install
cp .env.example .env         # then edit EXPO_PUBLIC_API_URL
pnpm tunnel                  # Metro + Expo Go tunnel
```

Scan the QR code in the terminal with the Expo Go app (iOS App Store / Play Store).

## Networking from a dev container

Metro listens on `8081` and Expo CLI uses `19000-19002`. Those are forwarded in
`.devcontainer/devcontainer.json`, so `pnpm start` works when the phone is on
the same LAN as the host.

For anywhere else (demo over cellular, reviewer on another network) use tunnel
mode — it relays through Expo's infrastructure so nothing has to be reachable
directly:

```bash
pnpm tunnel
```

The phone also needs to reach the **API** (port 5000). Two options:

1. **VS Code port forwarding → make public** — right-click the `5000` row in the
   Ports panel and set visibility to Public. Copy the generated URL into
   `apps/mobile/.env` as `EXPO_PUBLIC_API_URL`.
2. **Separate tunnel** — run `cloudflared tunnel --url http://localhost:5000`
   (or ngrok) in another terminal and use that URL.

Plain `http://localhost:5000` will only work for the web target (`pnpm web`),
not Expo Go on a physical phone.

## Scripts

- `pnpm start` — Metro in LAN mode
- `pnpm tunnel` — Metro in tunnel mode (works from anywhere)
- `pnpm web` — web preview at http://localhost:8081
- `pnpm ios` / `pnpm android` — open in local simulator/emulator (host-side)
