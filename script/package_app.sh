#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.8}"
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
ALLOW_UNNOTARIZED="${CMDIME_ALLOW_UNNOTARIZED:-0}"

find_codesign_identity() {
  local pattern="$1"
  security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'"' -v pattern="$pattern" '$0 ~ pattern {print $2; found=1; exit} END {exit found ? 0 : 1}'
}

default_codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf "%s" "$CODESIGN_IDENTITY"
    return
  fi

  find_codesign_identity '"Developer ID Application:' \
    || find_codesign_identity '"Apple Development:'
}

CODESIGN_IDENTITY="$(default_codesign_identity)"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

is_developer_id_identity() {
  [[ "$CODESIGN_IDENTITY" == Developer\ ID\ Application:* ]]
}

require_distribution_signing() {
  if is_developer_id_identity; then
    return
  fi

  if [[ "$ALLOW_UNNOTARIZED" == "1" ]]; then
    echo "warning: packaging with non-Developer ID signing identity; notarization will not be available." >&2
    return
  fi

  cat >&2 <<EOF
error: release packaging requires a Developer ID Application signing identity.

Current identity: $CODESIGN_IDENTITY

Install a Developer ID Application certificate, or run a local-only smoke build
with CMDIME_ALLOW_UNNOTARIZED=1. Do not publish local-only builds.
EOF
  exit 65
}

codesign_path() {
  local path="$1"
  local args=(--force --sign "$CODESIGN_IDENTITY")
  if [[ "$CODESIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    args+=(--options runtime --timestamp)
  else
    args+=(--timestamp=none)
  fi

  codesign "${args[@]}" "$path"
}

require_distribution_signing

rm -rf "$RELEASE_DIR" "$ZIP_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --product "$APP_NAME"
swift build -c release --product keyboardctl
BUILD_BIN_DIR="$(swift build -c release --show-bin-path)"

cp "$BUILD_BIN_DIR/$APP_NAME" "$APP_MACOS/$APP_NAME"
cp "$BUILD_BIN_DIR/keyboardctl" "$APP_MACOS/keyboardctl"
ln -s "../MacOS/keyboardctl" "$APP_RESOURCES/keyboardctl"
chmod +x "$APP_MACOS/$APP_NAME" "$APP_MACOS/keyboardctl"
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

codesign_path "$APP_MACOS/keyboardctl"
codesign_path "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$INFO_PLIST"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "$ZIP_PATH"
