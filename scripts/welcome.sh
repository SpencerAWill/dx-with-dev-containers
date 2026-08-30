#!/usr/bin/env bash
set -euo pipefail

echo ""
echo -e "\033[1;36m=== SnapSort Dev Container ===\033[0m"
echo ""
echo -e "  \033[1mStart services:\033[0m  F5 (API + Worker), then Run Task > web-app: dev"
echo -e "  \033[1mSeed data:\033[0m      Run Task > seed: load sample data"
echo -e "  \033[1mReset demo:\033[0m     Run Task > demo: reset"
echo -e "  \033[1mStatus page:\033[0m    http://localhost:5173/status   (in-container; host: see VS Code Ports panel)"
echo -e "  \033[1mAPI reference:\033[0m  http://localhost:5000/scalar    (in-container; host: see VS Code Ports panel)"
echo -e "  \033[1mMobile (Expo):\033[0m  pnpm mobile:tunnel  (scan QR in Expo Go)"
echo ""
