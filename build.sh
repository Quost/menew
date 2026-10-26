#!/bin/bash
# Compila e monta o MeuMenu.app em ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/MeuMenu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MeuMenu "$APP/Contents/MacOS/MeuMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Pronto: $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x MeuMenu 2>/dev/null || true
  rm -rf /Applications/MeuMenu.app
  cp -R "$APP" /Applications/
  open /Applications/MeuMenu.app
  echo "Instalado em /Applications"
fi
