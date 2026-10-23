#!/bin/bash
# Builds a distributable build/Glance-<version>.dmg: ad-hoc signed (no personal certificate),
# with the usual "drag Glance to Applications" window.
set -euo pipefail
cd "$(dirname "$0")"

CODESIGN_IDENTITY=- ./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Glance.app "$STAGE/"
xattr -cr "$STAGE/Glance.app"
ln -s /Applications "$STAGE/Applications"

DMG="build/Glance-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Glance $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
shasum -a 256 "$DMG"
