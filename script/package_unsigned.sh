#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="VPSMonitor"
BUNDLE_ID="ru.alexpm.VPSMonitor"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-unsigned.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-unsigned.zip"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"

echo "Building $APP_NAME $VERSION..."
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE" "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [ -f "$APP_ICON" ]; then
  cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key> <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key> <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key> <string>AppIcon</string>
  <key>CFBundleName</key> <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key> <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key> <string>$VERSION</string>
  <key>CFBundleVersion</key> <string>$VERSION</string>
  <key>CFBundlePackageType</key> <string>APPL</string>
  <key>LSMinimumSystemVersion</key> <string>$MIN_SYSTEM_VERSION</string>
  <key>NSLocalNetworkUsageDescription</key> <string>VPSMonitor connects to your servers over SSH to collect read-only status information.</string>
  <key>NSPrincipalClass</key> <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Creating ZIP..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Creating DMG..."
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$APP_BUNDLE" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "Package ready:"
du -h "$ZIP_PATH" "$DMG_PATH"
