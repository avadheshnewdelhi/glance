#!/bin/bash
# Publishes the version in Resources/Info.plist: builds Glance.dmg, tags vX.Y.Z, creates the GitHub
# release (notes from CHANGELOG.md), and points the Homebrew cask at it so `brew upgrade` picks it up.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=avadheshnewdelhi/glance
TAP=avadheshnewdelhi/homebrew-tap
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"

[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first."; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "Release from main."; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists; bump the version in Resources/Info.plist."; exit 1; }
CHANGES=$(awk -v v="## $VERSION" '$0 == v {found=1; next} found && /^## / {exit} found' CHANGELOG.md)
[ -n "$CHANGES" ] || { echo "Add a '## $VERSION' section to CHANGELOG.md."; exit 1; }

./package.sh
SHA=$(shasum -a 256 build/Glance.dmg | cut -d' ' -f1)
NOTES=$(mktemp)
WORK=$(mktemp -d)
trap 'rm -rf "$NOTES" "$WORK"' EXIT
cat > "$NOTES" <<NOTES
$CHANGES

## Install or update

- **Homebrew:** \`brew install --cask avadheshnewdelhi/tap/glance\`, or \`brew upgrade --cask glance\` if it's already installed ([tap](https://github.com/$TAP)).
- **Manual:** download **Glance.dmg** below and drag Glance into Applications. Glance isn't notarized by Apple, so allow the first launch in **System Settings › Privacy & Security › Open Anyway**.

Each build has a new signature, so macOS asks for camera access again after an update. Requires macOS 14 or later.

**SHA-256** \`Glance.dmg\`: \`$SHA\`
NOTES

git push -q origin main
git tag -a "$TAG" -m "Glance $VERSION"
git push -q origin "$TAG"
gh release create "$TAG" build/Glance.dmg --repo "$REPO" --title "Glance $VERSION" --notes-file "$NOTES" --latest

gh repo clone "$TAP" "$WORK/tap" -- -q
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$WORK/tap/Casks/glance.rb"
git -C "$WORK/tap" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" commit -qam "glance $VERSION"
git -C "$WORK/tap" push -q
echo "Released $TAG and updated the Homebrew cask."
