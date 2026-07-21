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

echo ""
echo "Released $TAG — https://github.com/taufiqxr/NightOwl/releases/tag/$TAG"
