#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.2}"
APP_NAME="CmdIME"
BUNDLE_ID="com.shunmei.cmd-ime"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.icns"

default_codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf "%s" "$CODESIGN_IDENTITY"
    return
  fi

  security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'"' '/"Apple Development:|"Developer ID Application:/{print $2; exit}'
}

CODESIGN_IDENTITY="$(default_codesign_identity)"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

rm -rf "$RELEASE_DIR" "$ZIP_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --product "$APP_NAME"
swift build -c release --product keyboardctl
BUILD_BIN_DIR="$(swift build -c release --show-bin-path)"

cp "$BUILD_BIN_DIR/$APP_NAME" "$APP_MACOS/$APP_NAME"
cp "$BUILD_BIN_DIR/keyboardctl" "$APP_RESOURCES/keyboardctl"
chmod +x "$APP_MACOS/$APP_NAME" "$APP_RESOURCES/keyboardctl"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Shunmei Cho</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>CmdIME listens for your configured keyboard shortcuts to switch input sources.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --timestamp=none --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$INFO_PLIST"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "$ZIP_PATH"
