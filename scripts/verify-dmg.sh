#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?Usage: verify-dmg.sh path/to/Digger.dmg}"
MOUNT_DIR="$(mktemp -d)"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null || true
  fi
  rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil verify "$DMG_PATH"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH"
MOUNTED=1
plutil -lint "$MOUNT_DIR/Digger.app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$MOUNT_DIR/Digger.app"
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]]
lipo -archs "$MOUNT_DIR/Digger.app/Contents/MacOS/Digger"
echo "DMG verified: signed app and Applications shortcut are present."
