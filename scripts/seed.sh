#!/usr/bin/env bash
set -euo pipefail

API_URL="${1:-http://localhost:5000}"

# Check if the API is running
if ! curl -s -o /dev/null -w '' "$API_URL/health" 2>/dev/null; then
  echo "Error: API is not running at $API_URL"
  echo "Start the API first (web-api: run task or dotnet run)"
  exit 1
fi

echo "Seeding sample images via $API_URL ..."

IMAGES=(
  "https://picsum.photos/id/237/800/600|puppy.jpg"
  "https://picsum.photos/id/1025/800/600|pug.jpg"
  "https://picsum.photos/id/1074/800/600|mountain-lake.jpg"
  "https://picsum.photos/id/139/800/600|laptop-desk.jpg"
  "https://picsum.photos/id/292/800/600|sports-car.jpg"
)

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

for entry in "${IMAGES[@]}"; do
  url="${entry%%|*}"
  filename="${entry##*|}"

  echo -n "  Downloading $filename ... "
  curl -sL -o "$TMPDIR/$filename" "$url"
  echo "done"

  echo -n "  Uploading $filename ... "
  result=$(curl -s -X POST "$API_URL/api/images" -F "file=@$TMPDIR/$filename;type=image/jpeg")
  id=$(echo "$result" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "created $id"
done

echo ""
echo "Seeded ${#IMAGES[@]} images. Open the gallery to watch classification progress."
