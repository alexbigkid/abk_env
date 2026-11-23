#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_testing-lib.sh - tests for testing-lib.sh, the harness of the review script tests, and a guard
# that no test script chains conditions after check_that with && (the chained part would never be counted).
# usage: test_testing-lib.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

# shellcheck disable=SC2034  # printed by check in testing-lib.sh
RUNNER="test_testing-lib"

# Print "<passed> <failed>" after running a check in a fresh harness: the check name, then its command.
harness_result() {
    # shellcheck disable=SC2016  # the single quotes are on purpose: the subshell expands them
    bash -c 'source "$1/../../project-board/scripts/testing-lib.sh"; shift; check_that "x" "$@" >/dev/null; echo "$PASSED $FAILED"' _ "$SCRIPT_DIR" "$@"
}

check_that "a true condition is counted as passed" [ "$(harness_result true)" = "1 0" ]
check_that "a false condition is counted as failed" [ "$(harness_result false)" = "0 1" ]
check_that "a failing command is counted as failed" [ "$(harness_result grep -q nothing /dev/null)" = "0 1" ]

# Succeed when no line of the given test scripts chains something after a check_that call with && or ||.
no_chained_checks() {
    local hits
    hits=$(grep -n -E 'check_that .*\] *(&&|\|\|) ' "$@" /dev/null | grep -v "^[^:]*:[0-9]*: *#")
    # shellcheck disable=SC2034  # printed by check in testing-lib.sh when the check fails
    OUT=$hits
    [ -z "$hits" ]
}
# Write a test script with a chained check_that and report whether the detector flags it.
detector_flags_a_chain() {
    local first='check_that "bad" [ 1 -eq 1 ]' second=' && [ 1 -eq 2 ]'
    printf '%s\n' "$first$second" > "$TEST_TMP/chained.sh"
    ! no_chained_checks "$TEST_TMP/chained.sh"
}
check_that "the chain detector really flags a chained check_that" detector_flags_a_chain
check_that "no test script chains conditions after check_that" no_chained_checks "$SCRIPT_DIR"/test_*.sh
check_that "no test script of the other skills does either" no_chained_checks "$SCRIPT_DIR"/../../*/scripts/test_*.sh

finish
