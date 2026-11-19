#!/bin/bash
# Creates a drag-to-install disk image from the signed Tuck app.
set -euo pipefail

app="${1:?Usage: package-dmg.sh <Tuck.app> <output.dmg>}"
image="${2:?Missing output DMG path}"
app="${app%/}"
if [[ "${app##*/}" != Tuck.app ]] || [[ ! -d "$app" ]]; then
    echo "Expected the signed Tuck.app bundle." >&2
    exit 1
fi
if [[ "$image" != *.dmg || -e "$image" || -L "$image" ]]; then
    echo "Expected a new .dmg output path." >&2
    exit 1
fi

resource_directory="$(cd "$(dirname "$0")" && pwd)/dmg"
codesign --verify --deep --strict "$app"
staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT
# Use verified wheels in a temporary environment so Finder is not needed on the CI runner.
python_command="${TUCK_DMG_PYTHON:-python3}"
if ! "$python_command" -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
    echo "DMG packaging requires Python 3.11 or later. Set TUCK_DMG_PYTHON to its executable." >&2
    exit 1
fi
"$python_command" -m venv "$staging_directory/venv"
"$staging_directory/venv/bin/python" -m pip --isolated --disable-pip-version-check install \
    --quiet --no-index --require-hashes \
    -r "$resource_directory/requirements.txt"
app="$(cd "$(dirname "$app")" && pwd)/Tuck.app"
swift "$resource_directory/draw-background.swift" "$staging_directory"
mkdir -p "$(dirname "$image")"
"$staging_directory/venv/bin/dmgbuild" -s "$resource_directory/layout.py" \
    -D "app=$app" -D "background=$staging_directory/background.tiff" \
    Tuck "$image"
hdiutil verify "$image"
