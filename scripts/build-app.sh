#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
OUTPUT_DIR="$ROOT_DIR/dist"

APP_NAME="${APP_NAME:-Digger}"
BUNDLE_ID="${BUNDLE_ID:-com.digger.app}"
VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

echo "Building release binary..."
swift build -c release

if [[ ! -f "$BUILD_DIR/digger" ]]; then
  echo "Release binary not found at $BUILD_DIR/digger"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$BUILD_DIR/digger" "$MACOS_DIR/$APP_NAME"

echo "Embedding frameworks..."
for framework in "$BUILD_DIR"/*.framework; do
  if [[ -e "$framework" ]]; then
    cp -R "$framework" "$FRAMEWORKS_DIR"
  fi
done

if command -v install_name_tool >/dev/null; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" || true
fi

if [[ -f "$ROOT_DIR/Sources/digger/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Sources/digger/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

for bundle in "$BUILD_DIR"/*.bundle "$BUILD_DIR"/*.resources; do
  if [[ -e "$bundle" ]]; then
    cp -R "$bundle" "$RESOURCES_DIR"
  fi
done

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
EOF

echo "App bundle created at: $APP_DIR"

if [[ -n "$SIGN_IDENTITY" ]]; then
  if ! command -v codesign >/dev/null; then
    echo "codesign not found; skipping signing"
    exit 1
  fi

  echo "Signing app with identity: $SIGN_IDENTITY"

  if [[ -d "$FRAMEWORKS_DIR" ]]; then
    for framework in "$FRAMEWORKS_DIR"/*.framework; do
      if [[ -e "$framework" ]]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$framework"
      fi
    done
  fi

  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
  echo "Signing complete"
else
  echo "SIGN_IDENTITY not set; app bundle is unsigned"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARY_PROFILE not set; cannot notarize"
    exit 1
  fi
  if ! command -v xcrun >/dev/null; then
    echo "xcrun not found; cannot notarize"
    exit 1
  fi

  ZIP_PATH="$OUTPUT_DIR/$APP_NAME.zip"
  echo "Notarizing app with profile: $NOTARY_PROFILE"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"
  spctl -a -vv "$APP_DIR"
  echo "Notarization complete"
fi
