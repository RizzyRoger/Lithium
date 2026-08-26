#!/bin/bash
# Builds Lithium.app into dist/ and ad-hoc signs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Lithium.app"

echo "==> Compiling (release)"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Lithium" "$APP/Contents/MacOS/Lithium"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Scripts/lithium-hostsd" "$APP/Contents/Resources/lithium-hostsd"
cp "$ROOT/Scripts/com.lithium.hostsd.plist" "$APP/Contents/Resources/com.lithium.hostsd.plist"
chmod +x "$APP/Contents/Resources/lithium-hostsd"

# An ad-hoc signature is enough to run locally and to be granted Automation
# access, but the signature changes on every rebuild, so macOS asks for
# permission again after each build.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Done: $APP"
echo "    Run with: open '$APP'"
