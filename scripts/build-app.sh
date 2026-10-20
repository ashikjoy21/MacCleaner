#!/bin/zsh
# Builds MacCleaner.app into ./build with Xcode (needed for App Intents). Usage: scripts/build-app.sh [--open]
# Requires XcodeGen (`brew install xcodegen`); the Xcode project is generated from project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project MacCleaner.xcodeproj -scheme MacCleaner -configuration Release \
    -derivedDataPath build/xcode build -quiet

rm -rf build/MacCleaner.app
cp -R build/xcode/Build/Products/Release/MacCleaner.app build/MacCleaner.app
# Register with Launch Services so Shortcuts, Spotlight and the Finder service pick up this copy.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/MacCleaner.app
/System/Library/CoreServices/pbs -update
echo "Built build/MacCleaner.app"
[[ "${1:-}" == "--open" ]] && open build/MacCleaner.app
true
