#!/bin/bash
# Builds a distributable build/Glance.dmg: ad-hoc signed (no personal certificate),
# with the usual "drag Glance to Applications" window.
set -euo pipefail
cd "$(dirname "$0")"

CODESIGN_IDENTITY=- ./build.sh
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Glance.app "$STAGE/"
xattr -cr "$STAGE/Glance.app"
ln -s /Applications "$STAGE/Applications"

DMG="build/Glance.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Glance" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
shasum -a 256 "$DMG"
