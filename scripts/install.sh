#!/bin/sh
# MacCleaner installer.
#
#   Install or update:   curl -fsSL https://github.com/__GITHUB_REPO__/releases/latest/download/install.sh | sh
#   A specific version:  curl -fsSL https://github.com/__GITHUB_REPO__/releases/latest/download/install.sh | sh -s -- --version 1.2.0
#   Uninstall:           curl -fsSL https://github.com/__GITHUB_REPO__/releases/latest/download/install.sh | sh -s -- --uninstall
#
# What it does: downloads MacCleaner.zip from GitHub Releases, checks its SHA-256 against latest.json, installs
# MacCleaner.app into /Applications (or ~/Applications), links the `maccleaner` command, and opens the app.
# Files downloaded with curl aren't quarantined, so macOS opens the app without a Gatekeeper prompt.
set -eu

REPO="__GITHUB_REPO__"
APP="MacCleaner"
BUNDLE_ID="__BUNDLE_ID__"
VERSION="latest"
OPEN_APP=1
ACTION="install"

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --uninstall) ACTION="uninstall"; shift ;;
        --no-open) OPEN_APP=0; shift ;;
        -h|--help) echo "Usage: install.sh [--version X.Y.Z] [--no-open] [--uninstall]"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "MacCleaner runs on macOS only."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 14 ] || fail "MacCleaner needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."

quit_app() {
    if pgrep -x "$APP" >/dev/null 2>&1; then
        osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
        i=0; while pgrep -x "$APP" >/dev/null 2>&1 && [ $i -lt 20 ]; do sleep 0.5; i=$((i+1)); done
        pkill -x "$APP" >/dev/null 2>&1 || true
    fi
}

remove_cli_links() {
    for link in /usr/local/bin/maccleaner "$HOME/.local/bin/maccleaner"; do
        if [ -L "$link" ]; then rm -f "$link"; fi
    done
}

if [ "$ACTION" = "uninstall" ]; then
    bold "Uninstalling $APP…"
    quit_app
    for dir in /Applications "$HOME/Applications"; do
        if [ -d "$dir/$APP.app" ]; then rm -rf "$dir/$APP.app" && echo "Removed $dir/$APP.app"; fi
    done
    remove_cli_links
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "Done. Full Disk Access entries can be removed in System Settings › Privacy & Security."
    exit 0
fi

if [ -n "${MACCLEANER_BASE_URL:-}" ]; then
    BASE="$MACCLEANER_BASE_URL"   # for testing a release before it's published
elif [ "$VERSION" = "latest" ]; then
    BASE="https://github.com/$REPO/releases/latest/download"
else
    BASE="https://github.com/$REPO/releases/download/v${VERSION#v}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

bold "Downloading $APP…"
curl -fsSL "$BASE/latest.json" -o "$TMP/latest.json" || fail "Couldn't reach $BASE/latest.json"
REMOTE_VERSION="$(plutil -extract version raw -o - "$TMP/latest.json")"
EXPECTED_SHA="$(plutil -extract sha256 raw -o - "$TMP/latest.json")"
curl -fL --progress-bar "$BASE/$APP.zip" -o "$TMP/$APP.zip" || fail "Download failed."

ACTUAL_SHA="$(shasum -a 256 "$TMP/$APP.zip" | cut -d' ' -f1)"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || fail "Checksum mismatch: the download may be corrupted or tampered with. Nothing was installed."

ditto -x -k "$TMP/$APP.zip" "$TMP/unzipped"
[ -d "$TMP/unzipped/$APP.app" ] || fail "The download doesn't contain $APP.app."

if [ -w /Applications ]; then DEST="/Applications"; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi

bold "Installing $APP $REMOTE_VERSION into $DEST…"
quit_app
rm -rf "$DEST/$APP.app"
ditto "$TMP/unzipped/$APP.app" "$DEST/$APP.app"
xattr -dr com.apple.quarantine "$DEST/$APP.app" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$APP.app" >/dev/null 2>&1 || true

# Command-line tool: link it somewhere on PATH.
CLI="$DEST/$APP.app/Contents/Helpers/maccleaner"
if [ -x "$CLI" ]; then
    remove_cli_links
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        ln -sf "$CLI" /usr/local/bin/maccleaner && LINKED=/usr/local/bin/maccleaner
    else
        mkdir -p "$HOME/.local/bin" && ln -sf "$CLI" "$HOME/.local/bin/maccleaner" && LINKED="$HOME/.local/bin/maccleaner"
        case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH_HINT=1 ;; esac
    fi
fi

echo
bold "✓ $APP $REMOTE_VERSION installed."
[ -n "${LINKED:-}" ] && echo "  Command line: maccleaner --items   (linked at $LINKED)"
[ -n "${PATH_HINT:-}" ] && echo "  Add ~/.local/bin to your PATH to use it:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
echo "  Uninstall: curl -fsSL https://github.com/$REPO/releases/latest/download/install.sh | sh -s -- --uninstall"

if [ "$OPEN_APP" -eq 1 ]; then open "$DEST/$APP.app"; fi
