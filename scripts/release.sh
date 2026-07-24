#!/bin/bash
# NightOwl release script — CHANGELOG.md-driven.
#
# Usage:
#   1. Bump CFBundleShortVersionString/CFBundleVersion in Resources/Info.plist
#   2. Add a "## [<version>] — <date>" section to CHANGELOG.md
#   3. Commit, then run:  ./scripts/release.sh
#
# The script refuses to release without a matching changelog section, a
# clean tree, and passing tests — then builds the zip and publishes a
# GitHub release whose notes are that changelog section.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"

# Gate 1: changelog section for this version must exist
NOTES=$(awk "/^## \\[$VERSION\\]/{flag=1; next} /^## \\[/{flag=0} flag" CHANGELOG.md)
if [ -z "$NOTES" ]; then
  echo "ERROR: CHANGELOG.md has no '## [$VERSION]' section — write the release notes first."
  exit 1
fi

# Gate 2: don't re-release an existing version. gh creates tags on the
# REMOTE, so a local-only check would miss every previous release —
# check both.
if git rev-parse "$TAG" >/dev/null 2>&1 \
   || [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
  echo "ERROR: tag $TAG already exists — bump the version in Resources/Info.plist first."
  exit 1
fi

# Gate 3: clean tree, pushed
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree is not clean — commit (or stash) first."
  exit 1
fi
git push --quiet

# Gate 4: tests must pass
bash tests/test-daemon-logic.sh

# Build + publish
./build.sh --release
mkdir -p dist
printf '%s\n' "$NOTES" > "dist/RELEASE_NOTES-$VERSION.md"
gh release create "$TAG" "dist/NightOwl-$VERSION.zip" "dist/NightOwl-$VERSION.pkg" \
  --title "NightOwl $VERSION" \
  --notes-file "dist/RELEASE_NOTES-$VERSION.md"

# Point the Homebrew tap (taufiqxr/homebrew-tap) at the new release. The
# release is already published at this point, so a tap failure warns
# instead of aborting — re-run the block by hand if it does.
if SHA256=$(shasum -a 256 "dist/NightOwl-$VERSION.zip" | awk '{print $1}'); then
  TAP_DIR=$(mktemp -d)
  if git clone --quiet --depth 1 git@github.com:taufiqxr/homebrew-tap.git "$TAP_DIR" 2>/dev/null \
     || git clone --quiet --depth 1 https://github.com/taufiqxr/homebrew-tap.git "$TAP_DIR"; then
    sed -i '' \
      -e "s|^  version \".*\"|  version \"$VERSION\"|" \
      -e "s|^  sha256 \".*\"|  sha256 \"$SHA256\"|" \
      "$TAP_DIR/Casks/nightowl.rb"
    git -C "$TAP_DIR" commit --quiet -am "nightowl $VERSION" \
      && git -C "$TAP_DIR" push --quiet \
      && echo "Tap updated — brew serves $VERSION" \
      || echo "WARNING: tap commit/push failed — update homebrew-tap/Casks/nightowl.rb manually (version $VERSION, sha256 $SHA256)"
    rm -rf "$TAP_DIR"
  else
    echo "WARNING: could not clone homebrew-tap — update Casks/nightowl.rb manually (version $VERSION, sha256 $SHA256)"
  fi
fi

echo ""
echo "Released $TAG — https://github.com/taufiqxr/NightOwl/releases/tag/$TAG"
