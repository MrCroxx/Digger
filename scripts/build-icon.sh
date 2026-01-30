#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_IMAGE="${1:-}"
OUTPUT_PATH="${2:-$ROOT_DIR/Sources/digger/Resources/AppIcon.icns}"

if [[ -z "$SOURCE_IMAGE" ]]; then
  echo "Usage: scripts/build-icon.sh <icon.png> [output.icns]"
  exit 1
fi

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "Source image not found: $SOURCE_IMAGE"
  exit 1
fi

if ! command -v sips >/dev/null; then
  echo "sips not found; cannot generate iconset"
  exit 1
fi

if ! command -v iconutil >/dev/null; then
  echo "iconutil not found; cannot generate icns"
  exit 1
fi

ICONSET_DIR="$(mktemp -d)"
ICONSET_PATH="$ICONSET_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_PATH"

sips -z 16 16 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_IMAGE" --out "$ICONSET_PATH/icon_512x512@2x.png" >/dev/null

mkdir -p "$(dirname "$OUTPUT_PATH")"
iconutil -c icns "$ICONSET_PATH" -o "$OUTPUT_PATH"

rm -rf "$ICONSET_DIR"

echo "ICNS created at: $OUTPUT_PATH"
