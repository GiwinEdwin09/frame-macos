#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --product Frame --disable-sandbox
APP="$PWD/dist/Frame.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Frame "$APP/Contents/MacOS/Frame"
swift scripts/make-icon.swift .build/Frame.iconset
iconutil -c icns .build/Frame.iconset -o "$APP/Contents/Resources/Frame.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Frame</string>
<key>CFBundleIdentifier</key><string>local.frame.video</string>
<key>CFBundleName</key><string>Frame</string>
<key>CFBundleDisplayName</key><string>Frame</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Frame</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
