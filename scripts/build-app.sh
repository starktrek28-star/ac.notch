#!/usr/bin/env bash
# Builds a universal (Intel + Apple Silicon) "AC Notch.app" and zips it.
# Needs macOS with the Swift toolchain (GitHub's macOS runners have it).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product ACNotch
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --product ACNotch --show-bin-path)"

APP="build/AC Notch.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ACNotch" "$APP/Contents/MacOS/ACNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Word lists and context data for the correction engine (see Resources/Language/ATTRIBUTION.md).
cp -R Resources/Language "$APP/Contents/Resources/Language"

# Ad-hoc signature (no paid Apple developer account needed).
codesign --force --sign - "$APP"
lipo -info "$APP/Contents/MacOS/ACNotch"

(cd build && ditto -c -k --keepParent "AC Notch.app" ACNotch.zip)
echo "Built build/ACNotch.zip"
