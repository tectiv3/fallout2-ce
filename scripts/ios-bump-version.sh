#!/usr/bin/env bash
# Increments the patch component of the iOS bundle version stored in
# os/ios/version.txt (gitignored). CMakeLists.txt reads that file at configure
# time and uses it for both CFBundleShortVersionString and CFBundleVersion.
set -euo pipefail

VERSION_FILE="os/ios/version.txt"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "1.3.0" > "$VERSION_FILE"
fi

current=""
read -r current < "$VERSION_FILE"

IFS='.' read -r major minor patch <<< "$current"

if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "iOS version file $VERSION_FILE has unexpected format: '$current'" >&2
  exit 1
fi

patch=$((patch + 1))
new_version="$major.$minor.$patch"

printf '%s\n' "$new_version" > "$VERSION_FILE"
echo "iOS version bumped to $new_version"
