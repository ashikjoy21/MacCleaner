#!/bin/zsh
# One-time setup: creates a self-signed code-signing certificate in its own keychain.
#
# Why: macOS ties Full Disk Access to an app's signature. Ad-hoc signatures change every build, so users would
# have to grant access again after each update. A certificate that stays the same keeps the grant across updates.
# It is not an Apple Developer ID: Gatekeeper still treats the app as unidentified, which is fine because
# install.sh downloads with curl, and curl downloads aren't quarantined.
#
# Keep ~/.maccleaner-signing safe and backed up; releases signed with a different certificate lose the grant.
set -euo pipefail
cd "$(dirname "$0")/.."
source release.env

DIR="$HOME/.maccleaner-signing"
KEYCHAIN="$DIR/signing.keychain-db"
mkdir -p "$DIR" && chmod 700 "$DIR"
[[ -f "$DIR/keychain-password" ]] || openssl rand -hex 24 > "$DIR/keychain-password"
chmod 600 "$DIR/keychain-password"
PASSWORD="$(cat "$DIR/keychain-password")"

if [[ ! -f "$KEYCHAIN" ]]; then
    security create-keychain -p "$PASSWORD" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"   # no auto-lock timeout
fi
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"

print_trust_step() {
    echo
    echo "Two one-time steps left. Run both:"
    echo "  1. Trust the certificate for code signing (asks for your password):"
    echo "     security add-trusted-cert -r trustRoot -p codeSign -k \"$KEYCHAIN\" \"$DIR/certificate.pem\""
    echo "  2. Let codesign find it by adding its keychain to your search list:"
    echo "     security list-keychains -d user -s ~/Library/Keychains/login.keychain-db \"$KEYCHAIN\""
}

in_search_list() { security list-keychains -d user | grep -q "$KEYCHAIN"; }

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$SIGNING_IDENTITY"; then
    if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$SIGNING_IDENTITY" && in_search_list; then
        echo "Signing identity \"$SIGNING_IDENTITY\" is ready."
    else
        print_trust_step
    fi
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGNING_IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$SIGNING_IDENTITY" \
    -out "$TMP/identity.p12" -passout pass:"$PASSWORD" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$SIGNING_IDENTITY" \
    -out "$TMP/identity.p12" -passout pass:"$PASSWORD"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
cp "$TMP/cert.pem" "$DIR/certificate.pem"
echo "Created \"$SIGNING_IDENTITY\" in $KEYCHAIN"
print_trust_step
