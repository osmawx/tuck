#!/bin/bash
# Imports the pinned release identity into an isolated keychain and signs the app.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TUCK_SIGNING_P12_BASE64:?Missing release PKCS#12}"
: "${TUCK_SIGNING_P12_PASSWORD:?Missing PKCS#12 password}"
: "${TUCK_SIGNING_CERT_SHA1:?Missing release certificate fingerprint}"
: "${TUCK_SPARKLE_DIR:?Missing Sparkle SDK}"
: "${TUCK_SPARKLE_PUBLIC_KEY:?Missing Sparkle public key}"
: "${TUCK_BUILD_NUMBER:?Missing release build number}"
: "${TUCK_VERSION:?Missing release version}"
if [[ ! "$TUCK_SIGNING_CERT_SHA1" =~ ^[A-F0-9]{40}$ ]]; then
    echo "Invalid release certificate fingerprint." >&2
    exit 1
fi

umask 077
signing_directory="$(mktemp -d)"
keychain="$signing_directory/signing.keychain-db"
keychain_password="$(/usr/bin/openssl rand -hex 32)"
search_list="$(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')"
previous_keychains=()
while IFS= read -r entry; do
    if [[ -n "$entry" ]]; then previous_keychains+=("$entry"); fi
done <<< "$search_list"
changed_search_list=false

# Restore the user's search list and remove the temporary identity on every exit.
cleanup() {
    if [[ "$changed_search_list" == true ]]; then
        security list-keychains -d user -s ${previous_keychains[@]+"${previous_keychains[@]}"} || true
    fi
    security delete-keychain "$keychain" 2>/dev/null || true
    rm -rf "$signing_directory"
}
trap cleanup EXIT
printf '%s' "$TUCK_SIGNING_P12_BASE64" | base64 -D > "$signing_directory/identity.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_directory/identity.p12" -k "$keychain" \
    -P "$TUCK_SIGNING_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$keychain_password" "$keychain" >/dev/null
rm "$signing_directory/identity.p12"

# Self-signed identities do not appear among Apple's valid Developer ID identities.
if ! security find-certificate -a -Z "$keychain" |
    grep -Fx "SHA-1 hash: $TUCK_SIGNING_CERT_SHA1" >/dev/null; then
    echo "The PKCS#12 does not contain the pinned Tuck release certificate." >&2
    exit 1
fi
# codesign also needs the temporary keychain in its search list to resolve a self-signed identity.
changed_search_list=true
security list-keychains -d user -s "$keychain" ${previous_keychains[@]+"${previous_keychains[@]}"}
TUCK_SIGNING_KEYCHAIN="$keychain" ./build.sh
