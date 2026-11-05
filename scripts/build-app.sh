#!/bin/bash
# Builds "Showready.app" into ./build. Run on a Mac with Xcode or the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --show-bin-path)/Showready"
[ -f "$BIN" ] || BIN=".build/apple/Products/Release/Showready"

APP="build/Showready.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Showready"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Showready</string>
  <key>CFBundleDisplayName</key><string>Showready</string>
  <key>CFBundleIdentifier</key><string>com.showready.app</string>
  <key>CFBundleExecutable</key><string>Showready</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will run it locally.
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
