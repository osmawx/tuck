#!/bin/bash
# Downloads the pinned Sparkle SDK for framework embedding and release signing.
set -euo pipefail

destination="${1:?Usage: fetch-sparkle.sh <empty directory>}"
version="2.10.1"
checksum="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
mkdir -p "$destination"
if [[ -n "$(ls -A "$destination")" ]]; then
    echo "Sparkle download destination must be empty." >&2
    exit 1
fi
archive="$destination/Sparkle.tar.xz"
curl --fail --silent --show-error --location --retry 3 --proto '=https' --proto-redir '=https' \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
    --output "$archive"
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c
tar -xf "$archive" -C "$destination"
