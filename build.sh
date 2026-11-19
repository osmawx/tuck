#!/bin/bash
# Builds Tuck.app (menu bar organizer) into ./build.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tuck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Retain the original bundle ID and signing identity to preserve permissions and settings.
SIGNING_IDENTITY="Hider Local Development"
if ! security find-certificate -c "$SIGNING_IDENTITY" >/dev/null 2>&1; then
    echo "Missing signing identity. Run ./setup-signing.sh once." >&2
    exit 1
fi
SIGNING_HASH=$(security find-certificate -c "$SIGNING_IDENTITY" -Z | awk '/SHA-1 hash:/ {print $3; exit}')

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Tuck"

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

# Pin identity to this certificate and bundle id so privacy grants survive rebuilds.
codesign --force --sign "$SIGNING_IDENTITY" --requirements "=designated => identifier \"com.local.hider\" and certificate leaf = H\"$SIGNING_HASH\"" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
