#!/bin/bash

#------------------------------------------------------------------------------
# gitRelease.sh - start a release: push the temporary tag rel-<type> on main.
#
# usage: gitRelease.sh patch|minor|major
#
# Called by the git aliases rel-patch, rel-minor and rel-major (setGitAliases.sh).
# Needs main checked out, clean and equal to origin/main, and no rel-* tag with a run in progress
# (a stale rel-* tag without a run is deleted, with a message).
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

REPO=$(git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')

# A rel-* tag on origin with a run in progress: refuse. Without one it is stale (a run that never got
# a runner, or that was cancelled): delete it and go on.
for OLD_REF in $(git ls-remote --tags origin "$TAG_PREFIX*" | cut -f2); do
    OLD_TAG=${OLD_REF#refs/tags/}
    RUNNING=$(gh run list --repo "$REPO" --branch "$OLD_TAG" --json status,url \
        --jq '[.[] | select(.status != "completed")] | first | .url // empty') ||
        die "Cannot check the runs of $OLD_TAG (gh failed)"
    [ -z "$RUNNING" ] || die "A release is already running ($OLD_TAG): $RUNNING"
    echo "Deleting stale tag $OLD_TAG (no run in progress)"
    git push -q origin ":$OLD_REF"
done

# Push the trigger straight from HEAD: no local tag is created (so none is left behind, none is signed).
git push -q origin "HEAD:refs/tags/$TAG"

echo "Release $1 started: https://github.com/$REPO/actions"
