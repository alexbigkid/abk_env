#!/bin/bash

#------------------------------------------------------------------------------
# gitRelease.sh - start a release: open a pull request that bumps VERSION.
#
# usage: gitRelease.sh patch|minor|major [--auto-merge]
#
# Called by the git aliases rel-patch, rel-minor and rel-major (setGitAliases.sh).
# Needs a clean working tree on an up-to-date main and no open release pull request.
# It creates the branch release/vX.Y.Z from main, bumps VERSION in a signed commit,
# pushes the branch (the push starts the pipeline) and opens the pull request "Release vX.Y.Z". The body lists the
# commits since the last tag. --auto-merge makes the pull request squash-merge itself
# when its checks are green. When the pull request is merged into main, the workflow
# release-tag.yml creates the tag vX.Y.Z (the pipeline never pushes to main).
#
# GIT_RELEASE_COMMIT_FLAGS (default -S) are the signing flags of the commit; tests set it.
#------------------------------------------------------------------------------
set -euo pipefail

MAIN_BRANCH="main"
BRANCH_PREFIX="release"
USAGE="usage: $(basename "$0") patch|minor|major [--auto-merge]"
COMMIT_FLAGS=${GIT_RELEASE_COMMIT_FLAGS:--S}

# Print an error and stop.
die() {
    echo "❌ $*" >&2
    exit 1
}

# Print the next version for "<current> <type>".
next_version() {
    local major minor patch
    IFS=. read -r major minor patch <<< "$1"
    case "$2" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "${major}.$((minor + 1)).0" ;;
        patch) echo "${major}.${minor}.$((patch + 1))" ;;
    esac
}

case "${1:-}" in
    patch|minor|major) TYPE=$1 ;;
    *) die "$USAGE" ;;
esac
AUTO_MERGE=""
case "${2:-}" in
    "") ;;
    --auto-merge) AUTO_MERGE=1 ;;
    *) die "$USAGE" ;;
esac

[ "$(git rev-parse --abbrev-ref HEAD)" = "$MAIN_BRANCH" ] || die "Must be on '$MAIN_BRANCH'"
[ -z "$(git status --porcelain)" ] || die "Working tree is not clean"
git fetch -q origin "$MAIN_BRANCH" || die "Cannot fetch origin"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$MAIN_BRANCH")" ] ||
    die "$MAIN_BRANCH is not up to date with origin/$MAIN_BRANCH (pull or push first)"
OPEN=$(gh pr list --state open --json headRefName \
    --jq "[.[] | select(.headRefName | startswith(\"$BRANCH_PREFIX/\"))] | length")
[ "$OPEN" = "0" ] || die "A release pull request is already open"

CURRENT=$(cat VERSION)
NEXT=$(next_version "$CURRENT" "$TYPE")
BRANCH="$BRANCH_PREFIX/v$NEXT"

LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -n "$LAST_TAG" ]; then RANGE="$LAST_TAG..HEAD"; else RANGE="HEAD"; fi
BODY="Release v$NEXT ($TYPE, from $CURRENT).

Changes since ${LAST_TAG:-the start}:
$(git log "$RANGE" --pretty='- %s')"

git checkout -q -b "$BRANCH"
echo "$NEXT" > VERSION
git add VERSION
# shellcheck disable=SC2086  # the flags are meant to split
git commit -q $COMMIT_FLAGS -m "Release v$NEXT"
git push -q -u origin "$BRANCH"
git checkout -q "$MAIN_BRANCH"

URL=$(gh pr create --base "$MAIN_BRANCH" --head "$BRANCH" --title "Release v$NEXT" --body "$BODY")
if [ -n "$AUTO_MERGE" ]; then gh pr merge "$URL" --auto --squash; fi
echo "$URL"
