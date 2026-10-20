#!/bin/zsh
# Builds MacCleaner.app into ./build. Usage: scripts/build-app.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MacCleaner
BIN="$(swift build -c release --show-bin-path)/MacCleaner"

APP=build/MacCleaner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacCleaner"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacCleaner</string>
    <key>CFBundleDisplayName</key><string>MacCleaner</string>
    <key>CFBundleIdentifier</key><string>in.co.lno.MacCleaner</string>
    <key>CFBundleExecutable</key><string>MacCleaner</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Clean Build Files with MacCleaner</string></dict>
            <key>NSMessage</key><string>cleanBuildFiles</string>
            <key>NSPortName</key><string>MacCleaner</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.folder</string></array>
        </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key><string>MacCleaner quits WhatsApp or Telegram before cleaning their files.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS can remember the Full Disk Access grant for this app.
codesign --force --deep --sign - "$APP"
echo "Built $APP"
[[ "${1:-}" == "--open" ]] && open "$APP"
true
