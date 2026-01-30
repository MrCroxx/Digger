#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
OUTPUT_DIR="$ROOT_DIR/dist"

ENV_FILE="$ROOT_DIR/.env.build"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

APP_NAME="${APP_NAME:-Digger}"
BUNDLE_ID="${BUNDLE_ID:-com.digger.app}"
VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
CREATE_DMG="${CREATE_DMG:-1}"
DMG_BG_SCRIPT="$ROOT_DIR/scripts/dmg-background.swift"
DMG_BG_PATH="$OUTPUT_DIR/dmg-background.png"
CONFIGURE_DMG="${CONFIGURE_DMG:-0}"
USE_CREATE_DMG="${USE_CREATE_DMG:-1}"
GENERATE_DMG_BG="${GENERATE_DMG_BG:-1}"

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
APP_ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

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

if [[ "$CREATE_DMG" == "1" ]]; then
  if [[ ! -f "$APP_ICON_PATH" ]]; then
    echo "App icon not found at $APP_ICON_PATH"
    exit 1
  fi

  INFO_PLIST_ICON=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)
  if [[ "$INFO_PLIST_ICON" != "AppIcon" && "$INFO_PLIST_ICON" != "AppIcon.icns" ]]; then
    echo "CFBundleIconFile is not set to AppIcon in $CONTENTS_DIR/Info.plist"
    exit 1
  fi

  if ! command -v iconutil >/dev/null; then
    echo "iconutil not found; cannot validate AppIcon.icns"
    exit 1
  fi

  ICONSET_DIR="$(mktemp -d)"
  if ! iconutil -c iconset -o "$ICONSET_DIR/AppIcon.iconset" "$APP_ICON_PATH"; then
    echo "Failed to inspect AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    exit 1
  fi

  if [[ ! -f "$ICONSET_DIR/AppIcon.iconset/icon_512x512.png" || ! -f "$ICONSET_DIR/AppIcon.iconset/icon_512x512@2x.png" ]]; then
    echo "AppIcon.icns missing 512x512 or 1024x1024 sizes"
    rm -rf "$ICONSET_DIR"
    exit 1
  fi

  rm -rf "$ICONSET_DIR"
fi

if [[ "$CREATE_DMG" == "1" ]]; then
  if ! command -v hdiutil >/dev/null; then
    echo "hdiutil not found; skipping DMG creation"
  elif ! command -v osascript >/dev/null; then
    echo "osascript not found; skipping DMG creation"
  else
    DMG_NAME="$APP_NAME-$VERSION"
    DMG_PATH="$OUTPUT_DIR/$DMG_NAME.dmg"

    CREATE_DMG_BIN=""
    if command -v npm >/dev/null; then
      NPM_GLOBAL_BIN="$(npm prefix -g)/bin"
      if [[ -x "$NPM_GLOBAL_BIN/create-dmg" ]]; then
        CREATE_DMG_BIN="$NPM_GLOBAL_BIN/create-dmg"
      fi
    fi

    if [[ "$USE_CREATE_DMG" == "1" ]]; then
      if [[ -z "$CREATE_DMG_BIN" ]]; then
        echo "npm create-dmg not found; install with: npm install --global create-dmg"
        exit 1
      fi

      echo "Building DMG image with create-dmg (npm)..."
      mkdir -p "$OUTPUT_DIR"
      rm -f "$DMG_PATH"

      CREATE_DMG_ARGS=(--overwrite)
      if [[ -n "$SIGN_IDENTITY" ]]; then
        CREATE_DMG_ARGS+=("--identity=$SIGN_IDENTITY")
      else
        CREATE_DMG_ARGS+=(--no-code-sign)
      fi

      "$CREATE_DMG_BIN" "${CREATE_DMG_ARGS[@]}" "$APP_DIR" "$OUTPUT_DIR"

      DMG_GENERATED_PATH="$OUTPUT_DIR/$APP_NAME $VERSION.dmg"
      if [[ -f "$DMG_GENERATED_PATH" ]]; then
        mv "$DMG_GENERATED_PATH" "$DMG_PATH"
        DMG_MOUNT_DIR="$(mktemp -d)"
        if hdiutil attach -mountpoint "$DMG_MOUNT_DIR" -nobrowse -noverify "$DMG_PATH" >/dev/null; then
          VOLUME_HAS_ICON=$(mdls -name kMDItemFSHasCustomIcon -raw "$DMG_MOUNT_DIR" 2>/dev/null || true)
          if [[ "$VOLUME_HAS_ICON" != "1" && "$VOLUME_HAS_ICON" != "true" && ! -f "$DMG_MOUNT_DIR/.VolumeIcon.icns" ]]; then
            echo "DMG volume icon not set on $DMG_PATH"
            hdiutil detach "$DMG_MOUNT_DIR" >/dev/null
            rm -rf "$DMG_MOUNT_DIR"
            exit 1
          fi
          hdiutil detach "$DMG_MOUNT_DIR" >/dev/null
        else
          echo "Failed to mount DMG for icon validation"
          rm -rf "$DMG_MOUNT_DIR"
          exit 1
        fi
        rm -rf "$DMG_MOUNT_DIR"
        echo "DMG created at: $DMG_PATH"
      else
        echo "Expected DMG output not found at $DMG_GENERATED_PATH"
        exit 1
      fi
    else
      DMG_TEMP_PATH="$OUTPUT_DIR/$DMG_NAME-temp.dmg"
      STAGING_DIR="$(mktemp -d)"
      MOUNT_DIR="$(mktemp -d)"
      DMG_WINDOW_WIDTH=640
      DMG_WINDOW_HEIGHT=360
      DMG_ICON_SIZE=96
      DMG_APP_POS_X=160
      DMG_APP_POS_Y=170
      DMG_APPS_POS_X=480
      DMG_APPS_POS_Y=170

      echo "Creating DMG staging folder..."
      rm -f "$DMG_TEMP_PATH" "$DMG_PATH"
      mkdir -p "$OUTPUT_DIR"
      cp -R "$APP_DIR" "$STAGING_DIR/"

      if [[ "$GENERATE_DMG_BG" == "1" ]]; then
        if [[ -f "$DMG_BG_SCRIPT" ]]; then
          echo "Rendering DMG background..."
          if ! swift "$DMG_BG_SCRIPT" "$DMG_BG_PATH" "$APP_NAME" "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT"; then
            echo "Failed to render DMG background; continuing without background"
            rm -f "$DMG_BG_PATH"
          fi
        else
          echo "DMG background script not found; skipping"
        fi
      else
        rm -f "$DMG_BG_PATH"
      fi

      if [[ -f "$DMG_BG_PATH" ]]; then
        mkdir -p "$STAGING_DIR/.background"
        cp "$DMG_BG_PATH" "$STAGING_DIR/.background/dmg-background.png"
        chflags hidden "$STAGING_DIR/.background" || true
      fi

      ln -s /Applications "$STAGING_DIR/Applications"
      echo "Building DMG image..."
      hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDRW "$DMG_TEMP_PATH"
      hdiutil attach -mountpoint "$MOUNT_DIR" -noverify -nobrowse "$DMG_TEMP_PATH"

      if [[ "$CONFIGURE_DMG" == "1" ]]; then
        echo "Configuring DMG window layout..."
        for attempt in {1..5}; do
          if osascript <<EOF
 tell application "Finder"
   set dmgFolder to POSIX file "$MOUNT_DIR" as alias
   open dmgFolder
   set current view of container window of dmgFolder to icon view
   set toolbar visible of container window of dmgFolder to false
   set statusbar visible of container window of dmgFolder to false
   set the bounds of container window of dmgFolder to {100, 100, 100 + $DMG_WINDOW_WIDTH, 100 + $DMG_WINDOW_HEIGHT}
   set viewOptions to the icon view options of container window of dmgFolder
   set arrangement of viewOptions to not arranged
   set icon size of viewOptions to $DMG_ICON_SIZE
   if exists file ".background:dmg-background.png" of dmgFolder then
     set background picture of viewOptions to file ".background:dmg-background.png" of dmgFolder
   end if
   set position of item "$APP_NAME.app" of container window of dmgFolder to {$DMG_APP_POS_X, $DMG_APP_POS_Y}
   set position of item "Applications" of container window of dmgFolder to {$DMG_APPS_POS_X, $DMG_APPS_POS_Y}
   delay 1
   close container window of dmgFolder
 end tell
EOF
          then
            break
          fi
          sleep 1
        done
      else
        echo "Skipping DMG Finder layout (CONFIGURE_DMG=0)"
      fi

      hdiutil detach "$MOUNT_DIR"

      echo "Compressing DMG..."
      hdiutil convert "$DMG_TEMP_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

      rm -rf "$STAGING_DIR" "$MOUNT_DIR" "$DMG_TEMP_PATH"
      echo "DMG created at: $DMG_PATH"
    fi
  fi
fi

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
