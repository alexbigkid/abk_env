#!/bin/bash

#------------------------------------------------------------------------------
# gitRelease.sh - start a release: push the temporary tag rel-<type> on main.
#
# usage: gitRelease.sh patch|minor|major
#
# Called by the git aliases rel-patch, rel-minor and rel-major (setGitAliases.sh).
# Needs main checked out, clean and equal to origin/main, and no rel-* tag on origin.
# The tag push starts the pipeline (one test run for the release). When every job passed,
# the release job (.github/scripts/release.sh) bumps VERSION through a pull request,
# squash-merges it, tags vX.Y.Z and deletes the rel-* tag; on a failure it only deletes the tag.
#------------------------------------------------------------------------------
set -euo pipefail

MAIN_BRANCH="main"
TAG_PREFIX="rel-"
USAGE="usage: $(basename "$0") patch|minor|major"

# Print an error and stop.
die() {
    echo "❌ $*" >&2
    exit 1
}

[ $# -eq 1 ] || die "$USAGE"
case "$1" in
    patch|minor|major) TAG="$TAG_PREFIX$1" ;;
    *) die "$USAGE" ;;
esac

[ "$(git rev-parse --abbrev-ref HEAD)" = "$MAIN_BRANCH" ] || die "Must be on '$MAIN_BRANCH'"
[ -z "$(git status --porcelain)" ] || die "Working tree is not clean"
git fetch -q origin "$MAIN_BRANCH" || die "Cannot fetch origin"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$MAIN_BRANCH")" ] ||
    die "$MAIN_BRANCH is not up to date with origin/$MAIN_BRANCH (pull or push first)"
[ -z "$(git ls-remote --tags origin "$TAG_PREFIX*")" ] || die "A release is already running (a $TAG_PREFIX* tag exists on origin)"

# -f: a leftover local tag of an earlier release must not block this one.
git tag -f "$TAG" > /dev/null
git push -q origin "refs/tags/$TAG"

REPO=$(git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
echo "Release $1 started: https://github.com/$REPO/actions"
