#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/scripts/build-config.sh"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
if [[ "$BUILD_CONFIGURATION" != "debug" && "$BUILD_CONFIGURATION" != "release" ]]; then
  echo "BUILD_CONFIGURATION must be debug or release"
  exit 1
fi
cd "$ROOT_DIR"
BUILD_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
OUTPUT_DIR="$ROOT_DIR/dist"

APP_NAME="${APP_NAME:-Digger}"
BUNDLE_ID="${BUNDLE_ID:-com.digger.app}"
VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
CREATE_DMG="${CREATE_DMG:-1}"
CREATE_ZIP="${CREATE_ZIP:-$CREATE_DMG}"
DIGGER_MAC_UNSIGNED="${DIGGER_MAC_UNSIGNED:-0}"
APP_ICON_PATH="$ROOT_DIR/Sources/digger/Resources/AppIcon.icns"

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

if [[ "$DIGGER_MAC_UNSIGNED" == "1" ]]; then
  if [[ -n "$SIGN_IDENTITY" || "$NOTARIZE" == "1" ]]; then
    echo "DIGGER_MAC_UNSIGNED=1 cannot be combined with SIGN_IDENTITY or NOTARIZE=1" >&2
    exit 1
  fi
elif [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Set SIGN_IDENTITY, or DIGGER_MAC_UNSIGNED=1 for an ad-hoc local build." >&2
  exit 1
fi
if [[ "$NOTARIZE" == "1" && -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required for notarization" >&2
  exit 1
fi
if [[ ! -f "$APP_ICON_PATH" ]]; then
  echo "App icon not found at $APP_ICON_PATH" >&2
  exit 1
fi

echo "Building $BUILD_CONFIGURATION binary..."
swift build -c "$BUILD_CONFIGURATION"

if [[ ! -f "$BUILD_DIR/digger" ]]; then
  echo "Binary not found at $BUILD_DIR/digger"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$BUILD_DIR/digger" "$MACOS_DIR/$APP_NAME"

if command -v install_name_tool >/dev/null; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"
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
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
EOF

echo "App bundle created at: $APP_DIR"

# Sign (and optionally notarize) before copying the app into the disk image.
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
  echo "No Apple signing identity configured; signing for local use only"
  codesign --force --sign - "$APP_DIR"
  codesign --verify --strict "$APP_DIR"
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

  ZIP_PATH="$OUTPUT_DIR/$APP_NAME-notarization.zip"
  echo "Notarizing app with profile: $NOTARY_PROFILE"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"
  spctl -a -vv "$APP_DIR"
  rm -f "$ZIP_PATH"
  echo "Notarization complete"
fi

# Validate the same signed/stapled app that goes into both archives.
/usr/bin/python3 "$ROOT_DIR/scripts/smoke_macos.py" "$APP_DIR"
ARCH="$(lipo -archs "$MACOS_DIR/$APP_NAME")"
case "$ARCH" in
  arm64) ;;
  x86_64) ARCH=x64 ;;
  *) echo "Build one architecture on a matching Mac; got: $ARCH" >&2; exit 1 ;;
esac
ARTIFACT="$OUTPUT_DIR/$APP_NAME-$VERSION-$ARCH"

if [[ "$CREATE_DMG" == "1" ]]; then
  STAGING_DIR="$(mktemp -d)"
  trap 'rm -rf "$STAGING_DIR"' EXIT
  ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
  ln -s /Applications "$STAGING_DIR/Applications"
  /usr/bin/python3 "$ROOT_DIR/scripts/create_macos_dmg.py" \
    "$STAGING_DIR" "$ARTIFACT.dmg" "$APP_ICON_PATH" "$APP_NAME"
  "$ROOT_DIR/scripts/verify-dmg.sh" "$ARTIFACT.dmg" "$APP_NAME"
  echo "DMG created at: $ARTIFACT.dmg"
fi

if [[ "$CREATE_ZIP" == "1" ]]; then
  rm -f "$ARTIFACT.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARTIFACT.zip"
  ZIP_CHECK_DIR="$(mktemp -d)"
  trap 'rm -rf "${STAGING_DIR:-}" "$ZIP_CHECK_DIR"' EXIT
  ditto -x -k "$ARTIFACT.zip" "$ZIP_CHECK_DIR"
  /usr/bin/python3 "$ROOT_DIR/scripts/smoke_macos.py" "$ZIP_CHECK_DIR/$APP_NAME.app"
  echo "ZIP created at: $ARTIFACT.zip"
fi
