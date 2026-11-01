#!/bin/bash
# Wraps a built app in the disk image people download: the app, an Applications shortcut, the Downstage background.
#   make-dmg.sh app-zip out.dmg    the zip is the release zip, so both downloads hold the same build, untouched
# Writes the window layout itself with dmgbuild, so it needs no Finder and no permission prompt.
# First time: python3 -m venv macapp/dmg/venv && macapp/dmg/venv/bin/pip install dmgbuild==1.6.5
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ZIP="$1"; DMG="$2"
STAGE="$(mktemp -d)"; ditto -x -k "$ZIP" "$STAGE"
APP="$(find "$STAGE" -maxdepth 1 -name '*.app' | head -1)"
VOL="$(basename "${APP%.app}")"
if [ -e "$DMG" ]; then mv "$DMG" "$(mktemp -d)/"; fi
"$HERE/venv/bin/dmgbuild" -s "$HERE/dmg-settings.py" -D app="$APP" -D bg="$HERE/background.tiff" "$VOL" "$DMG" >/dev/null
du -h "$DMG"
