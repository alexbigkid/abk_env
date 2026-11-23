#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_review-worktree.sh - tests for review-worktree.sh (local repos, no network).
# usage: test_review-worktree.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${REVIEW_WORKTREE_UNDER_TEST:-$SCRIPT_DIR/review-worktree.sh}
# shellcheck disable=SC1091  # testing-lib.sh is next to this script
source "$SCRIPT_DIR/testing-lib.sh"

export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
CASE_NO=0

# Create a repo with a fetched remote branch F/5/test (one extra file on it) and go into it.
new_repo() {
    CASE_NO=$((CASE_NO + 1))
    local dir="$TEST_TMP/case-$CASE_NO"
    mkdir -p "$dir"
    git init -q --bare "$dir/remote.git"
    git --git-dir="$dir/remote.git" symbolic-ref HEAD refs/heads/main
    git clone -q "$dir/remote.git" "$dir/work" 2>/dev/null
    cd "$dir/work" || exit 1
    git config user.name t
    git config user.email t@example.invalid
    echo base > base.txt
    git add base.txt
    git commit -q -m base
    git branch -M main
    git push -q origin main
    git checkout -q -b F/5/test
    echo pr > pr.txt
    git add pr.txt
    git commit -q -m "pr change"
    git push -q origin F/5/test
    git checkout -q main
    git fetch -q origin
}

# Run the whole suite with the current shell.
run_suite() {
    new_repo
    run_script add F/5/test
    wt=$OUT
    check_that "add succeeds and prints a directory" [ "$RC" -eq 0 ] && [ -d "$wt" ]
    check_that "the worktree has the files of the PR branch" [ -f "$wt/pr.txt" ]
    check_that "the worktree is detached at the tip of the remote branch" [ "$(git -C "$wt" rev-parse HEAD)" = "$(git rev-parse origin/F/5/test)" ] && [ -z "$(git -C "$wt" branch --show-current)" ]
    check_that "your own checkout stays on main without the PR file" [ "$(git branch --show-current)" = "main" ] && [ ! -f pr.txt ]
    run_script remove "$wt"
    check_that "remove deletes it and unregisters it" [ "$RC" -eq 0 ] && [ ! -d "$wt" ] && ! git worktree list | grep -q "review-wt"

    run_script add F/5/not-fetched
    check_that "an unfetched branch is refused with the fetch hint" [ "$RC" -ne 0 ] && grep -q "git fetch" <<<"$OUT"
    run_script remove "$TEST_TMP"
    check_that "removing a path the script did not create is refused" [ "$RC" -ne 0 ] && [ -d "$TEST_TMP" ]
    other=$(mktemp -d "$TEST_TMP/review-wt.XXXXXX")
    run_script remove "$other"
    check_that "a review-wt directory that is no registered worktree is refused" [ "$RC" -ne 0 ] && [ -d "$other" ]
    run_script
    check_that "no argument is a usage error" [ "$RC" -ne 0 ]
    run_script add
    check_that "add without a branch is a usage error" [ "$RC" -ne 0 ]
}

for_each_shell run_suite
finish
