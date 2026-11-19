#!/bin/bash
# Builds Tuck.app (menu bar organizer) into ./build.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tuck.app"
BUNDLE_ID="com.local.hider"
BUILD_NUMBER="${TUCK_BUILD_NUMBER:-1}"
VERSION="${TUCK_VERSION:-1.0}"
SPARKLE_DIR="${TUCK_SPARKLE_DIR:-}"
SPARKLE_PUBLIC_KEY="${TUCK_SPARKLE_PUBLIC_KEY:-}"

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ || ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "Invalid Tuck build number or version." >&2
    exit 1
fi
if [[ -n "$SPARKLE_DIR" && -z "$SPARKLE_PUBLIC_KEY" || -z "$SPARKLE_DIR" && -n "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "Set both TUCK_SPARKLE_DIR and TUCK_SPARKLE_PUBLIC_KEY to enable updates." >&2
    exit 1
fi

# Preserve the existing local identity. Release builds select the pinned certificate by hash.
SIGNING_HASH="${TUCK_SIGNING_CERT_SHA1:-}"
if [[ -z "$SIGNING_HASH" ]]; then
    SIGNING_IDENTITY="Hider Local Development"
    SIGNING_HASH=$(security find-certificate -c "$SIGNING_IDENTITY" -Z 2>/dev/null | awk '/SHA-1 hash:/ {print $3; exit}' || true)
fi
if [[ ! "$SIGNING_HASH" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo "Missing or invalid signing identity. For local builds run ./setup-signing.sh once." >&2
    exit 1
fi
SIGNING_OPTIONS=(--force --sign "$SIGNING_HASH" --timestamp=none)
if [[ -n "${TUCK_SIGNING_KEYCHAIN:-}" ]]; then
    SIGNING_OPTIONS+=(--keychain "$TUCK_SIGNING_KEYCHAIN")
fi
# A stable designated requirement keeps the same identity across versions signed with this certificate.
APP_REQUIREMENT="=designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$SIGNING_HASH\""

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

sources=()
while IFS= read -r -d '' source; do
    sources+=("$source")
done < <(find Sources -type f -name '*.swift' -print0)

if [[ -n "$SPARKLE_DIR" ]]; then
    mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources"
    cp "$SPARKLE_DIR/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
    ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
    build_directory=$(mktemp -d)
    trap 'rm -rf "$build_directory"' EXIT
    for architecture in arm64 x86_64; do
        swiftc -O -swift-version 5 -target "$architecture-apple-macos26.0" -F "$SPARKLE_DIR" -framework Sparkle \
            -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
            "${sources[@]}" -o "$build_directory/Tuck-$architecture"
    done
    lipo -create "$build_directory/Tuck-arm64" "$build_directory/Tuck-x86_64" -output "$APP/Contents/MacOS/Tuck"
    lipo "$APP/Contents/MacOS/Tuck" -verify_arch arm64 x86_64
else
    swiftc -O -swift-version 5 "${sources[@]}" -o "$APP/Contents/MacOS/Tuck"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tuck</string>
  <key>CFBundleDisplayName</key><string>Tuck</string>
  <key>CFBundleIdentifier</key><string>com.local.hider</string>
  <key>CFBundleExecutable</key><string>Tuck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

info="$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$info"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$info"
if [[ -n "$SPARKLE_DIR" ]]; then
    plutil -replace LSMinimumSystemVersion -string 26.0 "$info"
    plutil -insert SUFeedURL -string https://github.com/osmawx/tuck/releases/latest/download/appcast.xml "$info"
    plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$info"
    plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$info"
    plutil -insert SURequireSignedFeed -bool YES "$info"
    plutil -insert SUEnableAutomaticChecks -bool YES "$info"
    plutil -insert SUAutomaticallyUpdate -bool YES "$info"

    # Sign Sparkle from the innermost code outwards with the same certificate as Tuck.
    framework="$APP/Contents/Frameworks/Sparkle.framework"
    resources="$framework/Versions/Current"
    for component in "$resources/Autoupdate" "$resources/Updater.app" "$resources"/XPCServices/*.xpc "$framework"; do
        codesign "${SIGNING_OPTIONS[@]}" "$component"
    done
fi
codesign "${SIGNING_OPTIONS[@]}" --requirements "$APP_REQUIREMENT" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
