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
WORKTREE_ROOT=${REVIEW_WORKTREE_ROOT:-${TMPDIR:-/tmp}/abk-review-worktrees}

usage() {
    cat <<USAGE
usage: review-worktree.sh add <branch>      create a detached worktree of $REMOTE/<branch>, print its path
       review-worktree.sh root              print the directory all worktrees are created in (a headless run needs it as an extra allowed directory: cd outside the session directories is refused)
       review-worktree.sh remove <path>     remove such a worktree (only paths this script created)
       review-worktree.sh prune             remove all leftovers of earlier runs (worktrees and empty temp dirs)
The branch must be fetched first: with-https.sh git fetch $REMOTE <branch>
USAGE
}

# Create the worktree of a fetched remote branch and print its path.
cmd_add() {
    local branch=$1 dir
    git rev-parse --verify -q "refs/remotes/$REMOTE/$branch" >/dev/null ||
        die "$REMOTE/$branch is not fetched; run: with-https.sh git fetch $REMOTE $branch"
    mkdir -p "$WORKTREE_ROOT"
    dir=$(mktemp -d "$WORKTREE_ROOT/$WORKTREE_PREFIX.XXXXXX")
    dir=$(cd "$dir" && pwd -P)
    git worktree add -q --detach "$dir" "refs/remotes/$REMOTE/$branch" || { rmdir "$dir" 2>/dev/null; die "cannot create the worktree"; }
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

# Remove every review worktree of this repo and the empty temp dirs left by a failed or interrupted run.
cmd_prune() {
    local dir count=0
    while read -r dir; do
        [ -n "$dir" ] || continue
        if git worktree remove --force "$dir"; then count=$((count + 1)); fi
    done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | grep "/$WORKTREE_PREFIX\." || true)
    git worktree prune
    find "$WORKTREE_ROOT" -maxdepth 1 -type d -name "$WORKTREE_PREFIX.*" -empty -exec rmdir {} + 2>/dev/null || true
    echo "pruned: $count review worktree(s)"
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    add)    [ $# -eq 2 ] || usage_error ;;
    remove) [ $# -eq 2 ] || usage_error ;;
    prune)  [ $# -eq 1 ] || usage_error ;;
    root)   [ $# -eq 1 ] || usage_error ;;
    *)      usage_error ;;
esac
case "$1" in
    add)    cmd_add "$2" ;;
    remove) cmd_remove "$2" ;;
    prune)  cmd_prune ;;
    root)   echo "$WORKTREE_ROOT" ;;
esac
