#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_review-worktree.sh - tests for review-worktree.sh (local repos, no network).
# usage: test_review-worktree.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${REVIEW_WORKTREE_UNDER_TEST:-$SCRIPT_DIR/review-worktree.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

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

# Succeed when no worktree of this script is registered.
no_review_worktree() { ! git worktree list | grep -q "review-wt"; }

# Run the whole suite with the current shell.
run_suite() {
    new_repo
    run_script add F/5/test
    wt=$OUT
    check_that "add succeeds" [ "$RC" -eq 0 ]
    check_that "add prints a directory that exists" [ -d "$wt" ]
    check_that "the worktree has the files of the PR branch" [ -f "$wt/pr.txt" ]
    check_that "the worktree is at the tip of the remote branch" [ "$(git -C "$wt" rev-parse HEAD)" = "$(git rev-parse origin/F/5/test)" ]
    check_that "the worktree is detached" [ -z "$(git -C "$wt" branch --show-current)" ]
    check_that "your own checkout stays on main" [ "$(git branch --show-current)" = "main" ]
    check_that "your own checkout does not get the PR file" [ ! -f pr.txt ]
    run_script remove "$wt"
    check_that "remove succeeds" [ "$RC" -eq 0 ]
    check_that "remove deletes the directory" [ ! -d "$wt" ]
    check_that "remove unregisters the worktree" no_review_worktree

    run_script add F/5/not-fetched
    check_that "an unfetched branch is refused" [ "$RC" -ne 0 ]
    check_that "the refusal has the fetch hint" grep -q "git fetch" <<<"$OUT"
    check_that "the refused add leaves no directory behind" [ -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'review-wt.*' -newer "$TEST_TMP/gitconfig" 2>/dev/null | head -1)" ]
    run_script remove "$TEST_TMP"
    check_that "removing a path the script did not create is refused" [ "$RC" -ne 0 ]
    check_that "that path is still there" [ -d "$TEST_TMP" ]
    other=$(mktemp -d "$TEST_TMP/review-wt.XXXXXX")
    run_script remove "$other"
    check_that "a review-wt directory that is no registered worktree is refused" [ "$RC" -ne 0 ]
    check_that "and it is left alone" [ -d "$other" ]
    run_script add F/5/test
    leftover=$OUT
    run_script add F/5/test
    leftover2=$OUT
    run_script prune
    check_that "prune succeeds" [ "$RC" -eq 0 ]
    check_that "prune says how many it removed" [ "$OUT" = "pruned: 2 review worktree(s)" ]
    check_that "prune removed the first leftover worktree" [ ! -d "$leftover" ]
    check_that "prune removed the second leftover worktree" [ ! -d "$leftover2" ]
    check_that "prune left no registered worktree" no_review_worktree
    run_script prune
    check_that "prune with nothing to do says so" [ "$OUT" = "pruned: 0 review worktree(s)" ]
    run_script prune extra
    check_that "prune takes no argument" [ "$RC" -ne 0 ]
    run_script
    check_that "no argument is a usage error" [ "$RC" -ne 0 ]
    run_script add
    check_that "add without a branch is a usage error" [ "$RC" -ne 0 ]
}

for_each_shell run_suite
finish
