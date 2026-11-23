#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_review-state.sh - tests for review-state.sh (stubbed gh, no network).
# usage: test_review-state.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${REVIEW_STATE_UNDER_TEST:-$SCRIPT_DIR/review-state.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill, the others are next to this script
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/review-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/review-stub-lib.sh"

STUB_DIR="$TEST_TMP/stub"
make_gh_stub "$TEST_TMP/bin"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH" REVIEW_STATE_RETRY_WAIT=0

# Run the whole suite with the current shell.
run_suite() {
    set_pr none no 0
    run_script 5
    check_that "no open PR for the issue gives pr null" [ "$OUT" = '{"pr": null}' ]

    set_pr 0 no 0
    run_script 5
    check_that "the PR of the issue is picked (not the one of another issue)" [ "$(jq -r .pr <<<"$OUT")" = "7" ]
    check_that "a PR without reviews is round 0" [ "$(jq -r .round <<<"$OUT")" = "0" ]
    check_that "the cap is read from review-lib.sh" [ "$(jq -r .max <<<"$OUT")" = "$MAX_REVIEW_ROUNDS" ]
    check_that "round 0 is not capped" [ "$(jq -r .capped <<<"$OUT")" = "false" ]
    check_that "branch, base, head sha and node id are reported" [ "$(jq -r '"\(.branch) \(.base) \(.headSha) \(.id)"' <<<"$OUT")" = "F/5/test main $HEAD_SHA PR_node" ]
    check_that "there is no last review yet" [ "$(jq -r .lastReviewAt <<<"$OUT")" = "null" ]
    check_that "the PR lookup asks for the most recently updated PRs first" grep -q "UPDATED_AT" "$STUB_DIR/queries.log"

    set_pr 3 no 0
    run_script 5
    check_that "only reviews with the hidden tag count (a human review titled like ours does not)" [ "$(jq -r .round <<<"$OUT")" = "3" ]
    check_that "the time of the last round review is reported" [ -n "$(jq -r '.lastReviewAt | select(. != null)' <<<"$OUT")" ]

    set_pr $((MAX_REVIEW_ROUNDS - 1)) no 0
    run_script 5
    check_that "one round before the cap is not capped" [ "$(jq -r .capped <<<"$OUT")" = "false" ]
    set_pr "$MAX_REVIEW_ROUNDS" no 0
    run_script 5
    check_that "the cap round is capped" [ "$(jq -r .capped <<<"$OUT")" = "true" ]

    set_pr 1 new 2
    run_script 5
    check_that "the handled comment of the coder is returned" [ "$(jq -r '.handledComment | startswith("Review items handled:")' <<<"$OUT")" = "true" ]
    check_that "a human comment that only starts like it is not taken for the coder's summary" [ "$(jq -r '.handledComment | contains("fixed in abc")' <<<"$OUT")" = "true" ]
    check_that "a handled comment after the last review is new" [ "$(jq -r .handledIsNew <<<"$OUT")" = "true" ]
    check_that "unresolved threads are counted, resolved ones are not" [ "$(jq -r .unresolvedThreads <<<"$OUT")" = "2" ]
    set_pr 2 old 0
    run_script 5
    check_that "a handled comment from before the last review is not new" [ "$(jq -r .handledIsNew <<<"$OUT")" = "false" ]
    check_that "the old comment is still returned" [ "$(jq -r '.handledComment != null' <<<"$OUT")" = "true" ]
    set_pr 1 no 0
    run_script 5
    check_that "without a handled comment it is null (a human comment that only starts like the marker does not count)" [ "$(jq -r .handledComment <<<"$OUT")" = "null" ]
    check_that "without a handled comment it is not new" [ "$(jq -r .handledIsNew <<<"$OUT")" = "false" ]
    set_pr 2 edited 0
    run_script 5
    check_that "an edited summary counts as an answer (its edit time is used)" [ "$(jq -r .handledIsNew <<<"$OUT")" = "true" ]
    check_that "handledAt is the time of the edit" [ "$(jq -r .handledAt <<<"$OUT")" = "2026-11-23T22:00:00Z" ]
    set_pr 0 new 0
    run_script 5
    check_that "a handled comment before any review counts as new" [ "$(jq -r .handledIsNew <<<"$OUT")" = "true" ]

    set_pr 1 no 0 UNKNOWN
    rm -f "$STUB_DIR/queries.log"
    run_script 5
    check_that "an UNKNOWN mergeable state is read again twice, then reported as it is" [ "$(jq -r .mergeable <<<"$OUT")" = "UNKNOWN" ]
    check_that "that made three detail queries in all" [ "$(grep -c 'pullRequest(number' "$STUB_DIR/queries.log")" = "3" ]
    set_pr 1 no 0 MERGEABLE
    mv "$STUB_DIR/details.json" "$STUB_DIR/details.next"
    set_pr 1 no 0 UNKNOWN
    rm -f "$STUB_DIR/queries.log"
    run_script 5
    check_that "when the state becomes known on the re-read, that answer is used" [ "$(jq -r .mergeable <<<"$OUT")" = "MERGEABLE" ]
    check_that "and the re-read stops there (two detail queries)" [ "$(grep -c 'pullRequest(number' "$STUB_DIR/queries.log")" = "2" ]
    set_pr 1 no 0 MERGEABLE
    rm -f "$STUB_DIR/queries.log"
    run_script 5
    check_that "a known state is read once" [ "$(grep -c 'pullRequest(number' "$STUB_DIR/queries.log")" = "1" ]
    set_pr 1 no 0 CONFLICTING
    run_script 5
    check_that "merge conflicts are reported" [ "$(jq -r .mergeable <<<"$OUT")" = "CONFLICTING" ]
    set_pr 1 no 0
    run_script 5
    check_that "a clean PR is MERGEABLE" [ "$(jq -r .mergeable <<<"$OUT")" = "MERGEABLE" ]

    run_script abc
    check_that "a non-number is refused" [ "$RC" -ne 0 ]
    run_script
    check_that "no argument is a usage error" [ "$RC" -ne 0 ]
}

for_each_shell run_suite
finish
