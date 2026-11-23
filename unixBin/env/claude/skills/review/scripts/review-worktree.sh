#!/usr/bin/env bash

#------------------------------------------------------------------------------
# review-worktree.sh - check out a pull request branch in a separate throwaway worktree, so the
# reviewer can read the files and run tests and linters without touching the user's checkout.
# Needs: git. Run inside the repo; fetch the branch first (with-https.sh git fetch origin <branch>).
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$(dirname "$0")/../../project-board/scripts/lib.sh"

REMOTE="origin"
WORKTREE_PREFIX="review-wt"

usage() {
    cat <<USAGE
usage: review-worktree.sh add <branch>      create a detached worktree of $REMOTE/<branch>, print its path
       review-worktree.sh remove <path>     remove such a worktree (only paths this script created)
The branch must be fetched first: with-https.sh git fetch $REMOTE <branch>
USAGE
}

# Create the worktree of a fetched remote branch and print its path.
cmd_add() {
    local branch=$1 dir
    git rev-parse --verify -q "refs/remotes/$REMOTE/$branch" >/dev/null ||
        die "$REMOTE/$branch is not fetched; run: with-https.sh git fetch $REMOTE $branch"
    dir=$(mktemp -d "${TMPDIR:-/tmp}/$WORKTREE_PREFIX.XXXXXX")
    dir=$(cd "$dir" && pwd -P)
    git worktree add -q --detach "$dir" "refs/remotes/$REMOTE/$branch" || die "cannot create the worktree"
    echo "$dir"
}

# Remove a worktree that this script created.
cmd_remove() {
    local dir=$1 physical
    case "$dir" in
        */"$WORKTREE_PREFIX".*) ;;
        *) die "refusing to remove '$dir': not a $WORKTREE_PREFIX worktree" ;;
    esac
    physical=$(cd "$dir" 2>/dev/null && pwd -P) || die "'$dir' does not exist"
    git worktree list --porcelain | grep -q -x "worktree $physical" || die "'$dir' is not a registered worktree of this repo"
    dir=$physical
    git worktree remove --force "$dir"
    echo "removed: $dir"
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    add)    [ $# -eq 2 ] || usage_error ;;
    remove) [ $# -eq 2 ] || usage_error ;;
    *)      usage_error ;;
esac
case "$1" in
    add)    cmd_add "$2" ;;
    remove) cmd_remove "$2" ;;
esac
