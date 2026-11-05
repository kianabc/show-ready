#!/bin/bash
# Builds "Showready.app" into ./build. Run on a Mac with Xcode or the Command Line Tools.
#
#   ./scripts/build-app.sh            release build (default)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --show-bin-path)/Showready"
[ -f "$BIN" ] || BIN=".build/apple/Products/Release/Showready"

APP="build/Showready.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Showready"

# VERSION is the single source of truth — the plist, the git tag and the
# changelog all read from it, so they can't drift apart. CFBundleVersion must
# increase monotonically for the updater to compare builds; the commit count
# does that and stays meaningful.
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Rocco Show Ready</string>
  <key>CFBundleDisplayName</key><string>Rocco Show Ready</string>
  <key>CFBundleIdentifier</key><string>com.showready.app</string>
  <key>CFBundleExecutable</key><string>Showready</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>ShowreadyGitSHA</key><string>$SHA</string>
  <key>CFBundleIconFile</key><string>Showready</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Generated from scripts/make-icon.swift rather than checked in as a binary.
if [ ! -f "$ROOT/Resources/Showready.icns" ]; then
  mkdir -p "$ROOT/Resources"
  swift scripts/make-icon.swift >/dev/null \
    && iconutil -c icns build/Showready.iconset -o Resources/Showready.icns
fi
cp "$ROOT/Resources/Showready.icns" "$APP/Contents/Resources/Showready.icns"

# A Developer ID identity wins when present — that's the one that can be
# notarised. Otherwise ad-hoc, which is what CI and other people's Macs get.
if [ -n "${SHOWREADY_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SHOWREADY_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')"
else
  IDENTITY="-"
fi

# Notarisation requires a secure (Apple-issued) timestamp. Ad-hoc signing
# can't use one, and skipping it locally avoids a network round trip.
if [ "$IDENTITY" = "-" ]; then
  TIMESTAMP_FLAG="--timestamp=none"
else
  TIMESTAMP_FLAG="--timestamp"
fi

# Hardened runtime is mandatory for notarisation, and it is applied to local
# builds too so a problem surfaces here rather than at release time.
codesign --force --sign "$IDENTITY" \
  --options runtime \
  $TIMESTAMP_FLAG \
  "$APP"

echo "Built: $APP — v$VERSION ($BUILD, $SHA, signed by: $IDENTITY)"
