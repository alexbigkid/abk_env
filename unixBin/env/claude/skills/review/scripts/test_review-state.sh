#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_review-state.sh - tests for review-state.sh (stubbed gh, no network).
# usage: test_review-state.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${REVIEW_STATE_UNDER_TEST:-$SCRIPT_DIR/review-state.sh}
# shellcheck disable=SC1091  # testing-lib.sh is next to this script
source "$SCRIPT_DIR/testing-lib.sh"

STUB_DIR="$TEST_TMP/stub"
make_gh_stub "$TEST_TMP/bin"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH"

# Run the whole suite with the current shell.
run_suite() {
    set_pr none no 0
    run_script 5
    check_that "no open PR for the issue gives pr null" [ "$OUT" = '{"pr": null}' ]

    set_pr 0 no 0
    run_script 5
    check_that "the PR of the issue is picked (not the one of another issue)" [ "$(jq -r .pr <<<"$OUT")" = "7" ]
    check_that "a PR without reviews is round 0, not capped" [ "$(jq -r '"\(.round) \(.max) \(.capped)"' <<<"$OUT")" = "0 10 false" ]
    check_that "branch, base, head sha and node id are reported" [ "$(jq -r '"\(.branch) \(.base) \(.headSha) \(.id)"' <<<"$OUT")" = "F/5/test main abc123 PR_node" ]

    set_pr 3 no 0
    run_script 5
    check_that "only reviews that start with the round marker count (a human review does not)" [ "$(jq -r .round <<<"$OUT")" = "3" ]

    set_pr 9 no 0
    run_script 5
    check_that "round 9 of 10 is not capped yet" [ "$(jq -r .capped <<<"$OUT")" = "false" ]
    set_pr 10 no 0
    run_script 5
    check_that "round 10 of 10 is capped" [ "$(jq -r .capped <<<"$OUT")" = "true" ]

    set_pr 1 yes 2
    run_script 5
    check_that "the handled comment of the coder is returned" [ "$(jq -r '.handledComment | startswith("Review items handled:")' <<<"$OUT")" = "true" ]
    check_that "its time is returned" [ "$(jq -r .handledAt <<<"$OUT")" = "2026-11-23T20:00:00Z" ]
    check_that "unresolved threads are counted, resolved ones are not" [ "$(jq -r .unresolvedThreads <<<"$OUT")" = "2" ]
    set_pr 1 no 0
    run_script 5
    check_that "without a handled comment it is null" [ "$(jq -r .handledComment <<<"$OUT")" = "null" ]

    run_script abc
    check_that "a non-number is refused" [ "$RC" -ne 0 ]
    run_script
    check_that "no argument is a usage error" [ "$RC" -ne 0 ]
}

for_each_shell run_suite
finish
