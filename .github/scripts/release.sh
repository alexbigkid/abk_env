#!/usr/bin/env bash

#------------------------------------------------------------------------------
# release.sh - release job of the pipeline, started for a rel-<type> tag.
#
# usage: release.sh pass|fail
#
# fail: delete the rel-<type> tag and exit non-zero, so a run without a release is red.
# pass: bump VERSION on the branch release/vX.Y.Z with a commit made through the GitHub API
#       (GitHub signs it), open the pull request "Release vX.Y.Z", squash-merge it, tag
#       vX.Y.Z on the merge commit, delete the rel-<type> tag and the release branch.
#
# Needs GH_TOKEN (the run's GITHUB_TOKEN with contents and pull-requests write), GH_REPO,
# GITHUB_REF_NAME (the rel-<type> tag) and GITHUB_SHA (the commit the tag points to).
# When pass fails, the rel-<type> tag and the release branch (if this run created it) are deleted.
# Pushes and merges made with that token start no workflow, so no second test run starts.
#------------------------------------------------------------------------------
set -euo pipefail

RESULT=${1:-}
TAG=$GITHUB_REF_NAME
TYPE=${TAG#rel-}
MERGE_TRIES=10

# Delete a ref (tags/<name> or heads/<name>) on origin; a missing ref is fine.
delete_ref() {
    gh api -X DELETE "repos/$GH_REPO/git/refs/$1" > /dev/null || true
}

case "$RESULT" in
    fail) delete_ref "tags/$TAG"; echo "Tests did not pass: $TAG deleted, no release" >&2; exit 1 ;;
    pass) ;;
    *) echo "usage: release.sh pass|fail" >&2; exit 1 ;;
esac

# On any failure below the tag is removed, so a new release can start. The release branch is
# removed too when this run created it; deleting the head branch also closes an opened release PR.
BRANCH=""
BRANCH_CREATED=""
cleanup_failed_release() {
    local rc=$?
    [ $rc -eq 0 ] && return
    [ -z "$BRANCH_CREATED" ] || delete_ref "heads/$BRANCH"
    delete_ref "tags/$TAG"
}
trap cleanup_failed_release EXIT

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CURRENT=$(cat VERSION)
NEXT=$(bash "$SCRIPT_DIR/../../unixBin/nextVersion.sh" "$CURRENT" "$TYPE")
BRANCH="release/v$NEXT"

# main must still be the commit that was tested
MAIN_SHA=$(gh api "repos/$GH_REPO/git/ref/heads/main" --jq .object.sha)
[ "$MAIN_SHA" = "$GITHUB_SHA" ] || { echo "main moved since the tests started" >&2; exit 1; }

gh api "repos/$GH_REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$GITHUB_SHA" > /dev/null
BRANCH_CREATED=1
VERSION_BLOB=$(gh api "repos/$GH_REPO/contents/VERSION?ref=main" --jq .sha)
gh api -X PUT "repos/$GH_REPO/contents/VERSION" -f message="Release v$NEXT" \
    -f content="$(printf '%s\n' "$NEXT" | base64 | tr -d '\n')" -f sha="$VERSION_BLOB" -f branch="$BRANCH" > /dev/null

LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2> /dev/null || true)
RANGE=${LAST_TAG:+$LAST_TAG..}HEAD
BODY="Release v$NEXT ($TYPE, from $CURRENT).

Changes since ${LAST_TAG:-the start}:
$(git log "$RANGE" --pretty='- %s')"
PR_URL=$(gh pr create --base main --head "$BRANCH" --title "Release v$NEXT" --body "$BODY")

# The mergeability is computed in the background, so the first merge can be refused: retry.
for ((i = 1; i <= MERGE_TRIES; i++)); do
    gh pr merge "$PR_URL" --squash && break
    [ "$i" -lt "$MERGE_TRIES" ] || { echo "Cannot merge $PR_URL" >&2; exit 1; }
    sleep 6
done

MERGE_SHA=$(gh pr view "$PR_URL" --json mergeCommit --jq .mergeCommit.oid)
gh api "repos/$GH_REPO/git/refs" -f ref="refs/tags/v$NEXT" -f sha="$MERGE_SHA" > /dev/null
delete_ref "heads/$BRANCH"
delete_ref "tags/$TAG"
echo "Released v$NEXT ($MERGE_SHA) through $PR_URL"
