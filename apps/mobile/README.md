# SnapSort Mobile (Expo)

Expo Router app that lists and uploads images against the SnapSort API.

## First run

```bash
pnpm install                          # from the REPO ROOT — one pnpm workspace
cp apps/mobile/.env.example apps/mobile/.env   # then edit EXPO_PUBLIC_API_URL
pnpm mobile:tunnel                    # Metro + Expo Go tunnel
```

Scan the QR code in the terminal with the Expo Go app (iOS App Store / Play Store).

## Networking from a dev container

Two servers have to be reachable from the phone, so each gets its own
cloudflared quick tunnel:

```mermaid
graph LR
    Phone["Phone<br/>(Expo Go)"]

    subgraph Internet
        CfMetro["cloudflared<br/>quick tunnel"]
        CfApi["cloudflared<br/>quick tunnel"]
    end

    subgraph Dev Container
        Metro["Metro bundler<br/>:8081"]
        API["Web API<br/>:5000"]
    end

    Phone -->|"manifest + JS bundle"| CfMetro --> Metro
    Phone -->|"EXPO_PUBLIC_API_URL"| CfApi --> API
```

A quick tunnel maps one hostname to one port, so one tunnel cannot cover both.

`pnpm mobile:tunnel` (from the repo root) sets both up:

1. Tunnels the API and writes the URL into `.env` as `EXPO_PUBLIC_API_URL`.
2. Tunnels Metro and passes that URL to Expo as `EXPO_PACKAGER_PROXY_URL`, which
   overrides the dev server URL Expo advertises — so the manifest and bundle are
   fetched over the tunnel rather than from `localhost`.
3. Starts Expo. Scan the QR code with Expo Go.

Using cloudflared for Metro as well means Expo's own tunnel is not involved, so
`@expo/ngrok` is never downloaded (it is not in the lockfile). To fall back to
Expo's ngrok tunnel for Metro:

```bash
EXPO_TUNNEL=ngrok pnpm mobile:tunnel
```

### On the same LAN

Metro listens on `8081` and Expo CLI uses `19000-19002`. Those are forwarded in
`.devcontainer/devcontainer.json`, so plain `pnpm start` works when the phone is
on the same network as the host. The API still needs a reachable URL — either
right-click the `5000` row in the VS Code Ports panel and set visibility to
Public, or point `EXPO_PUBLIC_API_URL` at `http://<host-lan-ip>:5000`.

Plain `http://localhost:5000` only works for the web target (`pnpm web`), not
Expo Go on a physical phone.

## Scripts

Run these from `apps/mobile/`, or from the repo root as
`pnpm --filter mobile <script>`. Note that root-level `pnpm web` is the React web
app, while `pnpm web` here is the Expo web target.

- `pnpm start` — Metro in LAN mode
- `pnpm tunnel` — Metro in tunnel mode (works from anywhere)
- `pnpm web` — web preview at http://localhost:8081
- `pnpm ios` / `pnpm android` — open in local simulator/emulator (host-side)
