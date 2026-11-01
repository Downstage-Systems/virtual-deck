#!/bin/bash
# Developer ID signs a built app that carries Python and Node, inside out: every Mach-O file, then Python.app, the
# framework, and the app last. Each app's build.sh calls this in place of its ad hoc codesign.
#   sign-bundled-app.sh app sign-id bundle-id
set -euo pipefail
APP="$1"; ID="$2"; BID="$3"; HERE="$(cd "$(dirname "$0")" && pwd)"
SIGN=(codesign --force --options runtime --timestamp -s "$ID")
MAIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
PYFW="$APP/Contents/Frameworks/Python3.framework"; PYAPP="$PYFW/Versions/3.9/Resources/Python.app"
NODE="$(find "$APP/Contents/Resources" -type f -name node -perm +111 | head -1)"
# Node compiles JavaScript at runtime, which hardened code may only do with these
ENT="$(mktemp)"; cat > "$ENT" <<'PL'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/><key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/></dict></plist>
PL
export ID
find "$APP" -type f ! -path "$MAIN" ! -path "$PYAPP/Contents/MacOS/*" ! -path "$PYFW/Versions/3.9/Python3" ${NODE:+! -path "$NODE"} -print0 | xargs -0 -n 40 file -h --mime-type --print0 2>/dev/null \
  | python3 -c "
import sys
d=sys.stdin.buffer.read().split(b'\n')
for l in d:
    if b'\0' in l:
        p,t=l.split(b'\0',1)
        if b'mach-binary' in t or b'x-mach' in t: sys.stdout.buffer.write(p+b'\0')" \
  | xargs -0 -P 8 -n 1 codesign --force --options runtime --timestamp -s "$ID"
[ -n "$NODE" ] && "${SIGN[@]}" --entitlements "$ENT" "$NODE"
"${SIGN[@]}" "$PYFW/Versions/3.9/Python3"
"${SIGN[@]}" "$PYAPP"
"${SIGN[@]}" "$PYFW/Versions/3.9"
"${SIGN[@]}" --identifier "$BID" "$APP"
codesign --verify --deep --strict "$APP" && echo "signed $(basename "$APP")"
