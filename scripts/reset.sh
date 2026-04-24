#!/usr/bin/env bash
set -euo pipefail

# Run from repo root
cd "$(dirname "$0")/.."

echo "Resetting SnapSort demo data..."

echo -n "  Dropping database ... "
if ! dotnet ef database drop --project libs/data --startup-project apps/web-api --force > /dev/null 2>&1; then
  echo "failed (database may not exist)"
else
  echo "done"
fi

echo -n "  Recreating database with migrations ... "
if ! dotnet ef database update --project libs/data --startup-project apps/web-api > /dev/null 2>&1; then
  echo "failed"
  exit 1
else
  echo "done"
fi

echo ""
echo "Demo reset complete. Blob storage will be cleaned up as old"
echo "references are gone. Run 'seed: load sample data' to repopulate."
