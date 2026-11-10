#!/usr/bin/env bash
# Prints the next release version from git tags.
#   next-version.sh <patch|minor|major> <true|false: beta>
# No release tag yet: the first release takes the top "## x.y.z" heading in CHANGELOG.md.
# Beta: <next version>-betaN, N counting up from the betas already tagged for it.
set -euo pipefail
bump=${1:-patch}
beta=${2:-false}

latest=$(git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
if [ -z "$latest" ]; then
  version=$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+$' CHANGELOG.md | cut -c4- || true)
  [ -n "$version" ] || { echo "No release tags yet and no '## x.y.z' heading in CHANGELOG.md" >&2; exit 1; }
else
  IFS=. read -r major minor patch <<< "$latest"
  case "$bump" in
    major) version="$((major + 1)).0.0" ;;
    minor) version="$major.$((minor + 1)).0" ;;
    patch) version="$major.$minor.$((patch + 1))" ;;
    *) echo "bump must be patch, minor or major" >&2; exit 1 ;;
  esac
fi

if [ "$beta" = "true" ]; then
  n=$(git tag -l "$version-beta*" | wc -l)
  version="$version-beta$((n + 1))"
fi
echo "$version"
