#!/bin/bash
# Build Yap.app into ./build.  Usage: ./build.sh [--run | --install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product Yap
BIN="$(swift build -c release --show-bin-path)/Yap"

APP=build/Yap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Yap"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a real identity when there is one, so macOS remembers the
# mic / screen-recording permissions across rebuilds. Falls back to ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

case "${1:-}" in
  --run)
    pkill -x Yap 2>/dev/null || true
    open "$APP"
    ;;
  --install)
    pkill -x Yap 2>/dev/null || true
    rm -rf ~/Applications/Yap.app
    mkdir -p ~/Applications
    cp -R "$APP" ~/Applications/
    open ~/Applications/Yap.app
    echo "Installed to ~/Applications/Yap.app"
    ;;
esac
