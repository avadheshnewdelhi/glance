#!/bin/bash
# Builds build/Glance.app: sandboxed, hardened runtime, camera as its only entitlement.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Glance.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Glance" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# A real signing identity keeps the camera/Accessibility grants across rebuilds; ad-hoc ("-") works too.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -p codesigning -v | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --options runtime --entitlements Resources/Glance.entitlements --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
