#!/bin/bash
# Compila e empacota o MacMonitor.app. Use "./build.sh install" para copiar para /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/MacMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacMonitor "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP" >/dev/null
echo "✓ $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x MacMonitor 2>/dev/null || true
  rm -rf /Applications/MacMonitor.app
  cp -R "$APP" /Applications/
  open /Applications/MacMonitor.app
  echo "✓ Instalado em /Applications"
fi
