#!/usr/bin/env bash

#------------------------------------------------------------------------------
# nextVersion.sh - print the next version for a current version and a release type.
#
# usage: nextVersion.sh <major.minor.patch> patch|minor|major
#
# Used by the release job of the pipeline (.github/scripts/release.sh).
#------------------------------------------------------------------------------
set -euo pipefail

USAGE="usage: $(basename "$0") <major.minor.patch> patch|minor|major"
[[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$USAGE" >&2; exit 1; }

IFS=. read -r major minor patch <<< "$1"
case "${2:-}" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) echo "$USAGE" >&2; exit 1 ;;
esac
