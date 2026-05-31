#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────────
#  release.sh — build, sign, notarize and package VPSMonitor for distribution
#
#  Prerequisites (one-time setup):
#    1. Apple Developer Program account ($99/year)
#    2. Certificate "Developer ID Application" installed in Keychain
#       (Xcode → Settings → Accounts → Manage Certificates → +)
#    3. App-specific password for notarization
#       (appleid.apple.com → Sign-In Security → App-Specific Passwords)
#    4. Store credentials in a Keychain profile (one-time):
#         xcrun notarytool store-credentials VPSMonitor-Notary \
#           --apple-id "you@example.com" \
#           --team-id  "ABC1234DEF" \
#           --password "abcd-efgh-ijkl-mnop"
#
#  Then export these environment variables and run this script:
#    export DEV_ID_NAME="Developer ID Application: Your Name (ABC1234DEF)"
#    export NOTARY_PROFILE="VPSMonitor-Notary"
#    ./script/release.sh 1.1
#
#  Output: VPSMonitor-1.1.dmg next to the .app — ready for GitHub Releases.
# ───────────────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: $0 <version>  (e.g. $0 1.1)" >&2
  exit 2
fi

: "${DEV_ID_NAME:?Set DEV_ID_NAME to your Developer ID certificate's common name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your stored notarytool profile name}"

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
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"
ENTITLEMENTS="$DIST_DIR/$APP_NAME.entitlements"

cd "$ROOT_DIR"
export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"

echo "▶ Building release binary…"
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "▶ Assembling .app bundle…"
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
  <key>CFBundleExecutable</key>     <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>     <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>       <string>AppIcon</string>
  <key>CFBundleName</key>           <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key> <string>$VERSION</string>
  <key>CFBundleVersion</key>        <string>$VERSION</string>
  <key>CFBundlePackageType</key>    <string>APPL</string>
  <key>LSMinimumSystemVersion</key> <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>       <string>NSApplication</string>
</dict>
</plist>
PLIST

# Hardened runtime entitlements (required for notarization)
cat >"$ENTITLEMENTS" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key> <false/>
  <key>com.apple.security.cs.disable-library-validation</key>       <false/>
</dict>
</plist>
XML

echo "▶ Signing with Developer ID…"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEV_ID_NAME" \
  "$APP_BUNDLE"

echo "▶ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "▶ Creating .zip for notarization…"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "▶ Submitting to Apple notarization service (may take 2-5 min)…"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "▶ Stapling notarization ticket to .app…"
xcrun stapler staple "$APP_BUNDLE"

echo "▶ Creating .dmg…"
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$APP_BUNDLE" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "▶ Re-stapling .dmg…"
xcrun stapler staple "$DMG_PATH"

# Refresh the .zip with the stapled .app
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo ""
echo "✓ Release ready:"
echo "    $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"
echo "    $ZIP_PATH ($(du -h "$ZIP_PATH" | awk '{print $1}'))"
echo ""
echo "Next steps:"
echo "  1. git tag v$VERSION && git push origin v$VERSION"
echo "  2. gh release create v$VERSION \"$DMG_PATH\" \"$ZIP_PATH\" \\"
echo "       --title \"VPSMonitor $VERSION\" \\"
echo "       --notes \"…release notes here…\""
