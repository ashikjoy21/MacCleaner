#!/bin/zsh
# Builds a release of MacCleaner into dist/v<version>/ and, with --publish, uploads it to GitHub Releases.
#
#   scripts/release.sh 1.2.0                     build and check locally
#   scripts/release.sh 1.2.0 --notes notes.md    with release notes (Markdown)
#   scripts/release.sh 1.2.0 --publish           also tag, push and create the GitHub release
#
# Output: MacCleaner.zip (universal app with the `maccleaner` CLI inside), latest.json (version, URL, SHA-256)
# and install.sh, the three files the installer and the app's update check download.
set -euo pipefail
cd "$(dirname "$0")/.."
source release.env

VERSION="${1:?Usage: scripts/release.sh <version> [--notes file] [--publish]}"
VERSION="${VERSION#v}"
shift
NOTES_FILE=""
PUBLISH=0
while (( $# )); do
    case "$1" in
        --notes) NOTES_FILE="$2"; shift 2 ;;
        --publish) PUBLISH=1; shift ;;
        *) echo "Unknown option $1" >&2; exit 2 ;;
    esac
done
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Version must look like 1.2.0" >&2; exit 2; }
grep -q "MCGitHubRepo: $GITHUB_REPO" project.yml || { echo "project.yml MCGitHubRepo doesn't match GITHUB_REPO in release.env" >&2; exit 1; }

BUILD_NUMBER="$(git rev-list --count HEAD)"
OUT="dist/v$VERSION"
DERIVED="build/release"
rm -rf "$OUT" "$DERIVED"
mkdir -p "$OUT"

echo "▸ Building $APP_NAME $VERSION ($BUILD_NUMBER), universal"
xcodegen generate --quiet
xcodebuild -project MacCleaner.xcodeproj -scheme MacCleaner -configuration Release -derivedDataPath "$DERIVED" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="-" build -quiet
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"

echo "▸ Building the maccleaner command-line tool"
swift build -c release --product cleanerctl --arch arm64 --arch x86_64 >/dev/null
mkdir -p "$APP/Contents/Helpers"
cp "$(swift build -c release --product cleanerctl --arch arm64 --arch x86_64 --show-bin-path)/cleanerctl" "$APP/Contents/Helpers/maccleaner"

echo "▸ Signing"
KEYCHAIN="$HOME/.maccleaner-signing/signing.keychain-db"
SIGN=(-)
if [[ -f "$KEYCHAIN" ]]; then
    security unlock-keychain -p "$(cat "$HOME/.maccleaner-signing/keychain-password")" "$KEYCHAIN"
    if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$SIGNING_IDENTITY"; then
        SIGN=("$SIGNING_IDENTITY" --keychain "$KEYCHAIN")
    fi
fi
if [[ "${SIGN[1]}" == "-" ]]; then
    echo "  ⚠ Using an ad-hoc signature: Full Disk Access won't carry over to the next update."
    echo "    Run scripts/setup-signing.sh and follow its last step to fix this."
fi
codesign --force --options runtime --sign "${SIGN[@]}" --identifier "$BUNDLE_ID.cli" "$APP/Contents/Helpers/maccleaner"
codesign --force --options runtime --sign "${SIGN[@]}" "$APP"
codesign --verify --strict --deep "$APP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME" | grep -q "x86_64 arm64\|arm64 x86_64" || { echo "Not a universal binary" >&2; exit 1; }

echo "▸ Packaging"
ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME.zip"
SHA="$(shasum -a 256 "$OUT/$APP_NAME.zip" | cut -d' ' -f1)"
NOTES=""
[[ -n "$NOTES_FILE" ]] && NOTES="$(cat "$NOTES_FILE")"
python3 - "$OUT/latest.json" "$VERSION" "$BUILD_NUMBER" "$SHA" "$GITHUB_REPO" "$APP_NAME" "$NOTES" <<'PY'
import json, sys, datetime
out, version, build, sha, repo, app, notes = sys.argv[1:]
json.dump({
    "version": version, "build": int(build), "sha256": sha,
    "url": f"https://github.com/{repo}/releases/download/v{version}/{app}.zip",
    "notes": notes, "minimumSystemVersion": "14.0",
    "published": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}, open(out, "w"), indent=2)
PY
sed -e "s|__GITHUB_REPO__|$GITHUB_REPO|g" -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" scripts/install.sh > "$OUT/install.sh"
chmod +x "$OUT/install.sh"

echo
echo "✓ $OUT"
ls -lh "$OUT" | tail -n +2 | awk '{print "   " $5 "\t" $9}'

if (( PUBLISH )); then
    [[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes before publishing." >&2; exit 1; }
    echo "▸ Publishing v$VERSION to github.com/$GITHUB_REPO"
    git tag -a "v$VERSION" -m "$APP_NAME $VERSION"
    git push origin HEAD "v$VERSION"
    NOTES_ARGS=(--generate-notes)
    [[ -n "$NOTES_FILE" ]] && NOTES_ARGS=(--notes-file "$NOTES_FILE")
    gh release create "v$VERSION" "$OUT/$APP_NAME.zip" "$OUT/latest.json" "$OUT/install.sh" \
        --repo "$GITHUB_REPO" --title "$APP_NAME $VERSION" "${NOTES_ARGS[@]}"
    echo "✓ Published. Install with:"
    echo "  curl -fsSL https://github.com/$GITHUB_REPO/releases/latest/download/install.sh | sh"
else
    echo "Not published. Run again with --publish to tag and upload."
fi
