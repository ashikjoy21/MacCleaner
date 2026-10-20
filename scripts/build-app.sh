#!/bin/zsh
# Builds MacCleaner.app into ./build with Xcode (needed for App Intents).
# Usage: scripts/build-app.sh [--install] [--open]
# Requires XcodeGen (`brew install xcodegen`); the Xcode project is generated from project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project MacCleaner.xcodeproj -scheme MacCleaner -configuration Release \
    -derivedDataPath build/xcode build -quiet

rm -rf build/MacCleaner.app
cp -R build/xcode/Build/Products/Release/MacCleaner.app build/MacCleaner.app
touch build/.metadata_never_index  # keep build copies out of Spotlight
echo "Built build/MacCleaner.app"

# --install replaces /Applications/MacCleaner.app and registers it, so Shortcuts, Spotlight and the
# Finder service use the installed copy.
if [[ " $* " == *" --install "* ]]; then
    pkill -x MacCleaner || true
    rm -rf /Applications/MacCleaner.app
    ditto build/MacCleaner.app /Applications/MacCleaner.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MacCleaner.app
    /System/Library/CoreServices/pbs -update
    mdimport /Applications/MacCleaner.app
    echo "Installed /Applications/MacCleaner.app"
fi
if [[ " $* " == *" --open "* ]]; then
    [[ " $* " == *" --install "* ]] && open /Applications/MacCleaner.app || open build/MacCleaner.app
fi
true
