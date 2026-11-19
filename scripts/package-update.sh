#!/bin/bash
# Packages a signed app and produces a verified Sparkle appcast for its release.
set -euo pipefail

app="${1:?Usage: package-update.sh <app> <empty release directory> <GitHub tag>}"
destination="${2:?Missing release directory}"
tag="${3:?Missing GitHub tag}"
sparkle="${TUCK_SPARKLE_DIR:?Missing Sparkle SDK directory}"
: "${TUCK_SPARKLE_PRIVATE_KEY:?Missing Sparkle private key}"

mkdir -p "$destination"
if [[ -n "$(ls -A "$destination")" ]]; then
    echo "Release package destination must be empty." >&2
    exit 1
fi
script_directory="$(cd "$(dirname "$0")" && pwd)"
if [[ ! "$tag" =~ ^v1\.0\.[1-9][0-9]*$ ]]; then
    echo "Invalid Tuck release tag." >&2
    exit 1
fi
public_key="$(printf '%s' "$TUCK_SPARKLE_PRIVATE_KEY" | swift "$script_directory/sparkle-public-key.swift")"
embedded_key="$(plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist")"
if [[ "$public_key" != "$embedded_key" ]]; then
    echo "Sparkle signing key does not match the app's embedded public key." >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
zip="$destination/Tuck.zip"
feed="$destination/appcast.xml"
ditto -c -k --keepParent "$app" "$zip"
printf '%s\n' "$TUCK_SPARKLE_PRIVATE_KEY" |
    "$sparkle/bin/generate_appcast" --ed-key-file - --maximum-deltas 0 \
        --download-url-prefix "https://github.com/osmawx/tuck/releases/download/$tag/" "$destination"
signature="$(xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' "$feed")"
test -n "$signature"
printf '%s\n' "$TUCK_SPARKLE_PRIVATE_KEY" | "$sparkle/bin/sign_update" --ed-key-file - --verify "$zip" "$signature"
printf '%s\n' "$TUCK_SPARKLE_PRIVATE_KEY" | "$sparkle/bin/sign_update" --ed-key-file - --verify "$feed"
