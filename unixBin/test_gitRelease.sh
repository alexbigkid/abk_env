#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_gitRelease.sh - tests for gitRelease.sh.
#
# Self-contained: local bare repo as origin, no network, no GPG key. Never touches
# GitHub or your git config. Runs once per shell found.
#
# usage: test_gitRelease.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_UNDER_TEST=$SCRIPT_DIR/gitRelease.sh
CASE_NO=0

# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/env/claude/skills/project-board/scripts/testing-lib.sh"
handle_test_help "$@"

export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" user.name "Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "test@example.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

# New case: origin + clone on main with one commit, pushed.
new_repo() {
    CASE_NO=$((CASE_NO + 1))
    CASE_DIR=$TEST_TMP/case$CASE_NO
    mkdir -p "$CASE_DIR"
    git init -q --bare "$CASE_DIR/origin.git"
    git clone -q "$CASE_DIR/origin.git" "$CASE_DIR/work" 2>/dev/null
    cd "$CASE_DIR/work" || exit 1
    git checkout -q -b main
    echo "1.2.3" > VERSION
    git add VERSION && git commit -q -m "first"
    git push -q -u origin main 2>/dev/null
}

# Run the script in the current repo; sets OUT and RC.
run_rel() {
    OUT=$("$RUNNER" "$SCRIPT_UNDER_TEST" "$@" 2>&1)
    RC=$?
}

# Check that the script refused: name, expected text of the message, then its arguments.
expect_refused() {
    local name=$1 text=$2
    shift 2
    run_rel "$@"
    check_that "$name: refused" [ "$RC" -ne 0 ]
    check_that "$name: message" grep -q "$text" <<< "$OUT"
    check_that "$name: no new tag pushed" [ -z "$(git ls-remote --tags origin 'rel-*' | grep -v "${KEEP_TAG:-^$}")" ]
}

# Check one release type: pushes rel-<type> on the HEAD of main.
expect_tag() {
    local type=$1
    new_repo
    run_rel "$type"
    check_that "$type: succeeds" [ "$RC" -eq 0 ]
    check_that "$type: tag rel-$type on origin at HEAD" [ "$(git ls-remote origin "refs/tags/rel-$type" | cut -f1)" = "$(git rev-parse HEAD)" ]
    check_that "$type: prints the run link" grep -q "actions" <<< "$OUT"
    check_that "$type: back on main, VERSION untouched" [ "$(cat VERSION)" = "1.2.3" ]
}

run_suite() {
    expect_tag patch
    expect_tag minor
    expect_tag major

    new_repo
    echo dirty > VERSION
    expect_refused "dirty tree" "not clean" patch

    new_repo
    echo new > untracked.txt
    expect_refused "untracked file" "not clean" patch

    new_repo
    git checkout -q -b other
    expect_refused "not on main" "main" patch

    new_repo
    echo b > b.txt && git add b.txt && git commit -q -m "second" && git push -q origin main 2>/dev/null
    git reset -q --hard HEAD~1
    expect_refused "main behind origin" "up to date" patch

    new_repo
    echo b > b.txt && git add b.txt && git commit -q -m "local only"
    expect_refused "main ahead of origin" "up to date" patch

    new_repo
    git tag rel-minor && git push -q origin rel-minor 2>/dev/null
    KEEP_TAG=rel-minor expect_refused "existing rel tag" "already running" patch

    new_repo
    expect_refused "unknown type" "usage" bogus

    new_repo
    expect_refused "no type" "usage"
}

for_each_shell run_suite
finish
