#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_nextVersion.sh - tests for nextVersion.sh.
# usage: test_nextVersion.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_UNDER_TEST=$SCRIPT_DIR/nextVersion.sh

# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/env/claude/skills/project-board/scripts/testing-lib.sh"
handle_test_help "$@"

# Check the output: current version, type, expected next version.
expect_next() {
    OUT=$("$RUNNER" "$SCRIPT_UNDER_TEST" "$1" "$2" 2>&1)
    check_that "$1 $2 -> $3" [ "$OUT" = "$3" ]
}

# Check a refusal: name, then the arguments.
expect_refused() {
    local name=$1
    shift
    "$RUNNER" "$SCRIPT_UNDER_TEST" "$@" >/dev/null 2>&1
    check_that "$name: refused" [ "$?" -ne 0 ]
}

run_suite() {
    expect_next 1.2.3 patch 1.2.4
    expect_next 1.2.3 minor 1.3.0
    expect_next 1.2.3 major 2.0.0
    expect_next 1.9.9 patch 1.9.10
    expect_next 0.0.0 minor 0.1.0
    expect_refused "unknown type" 1.2.3 bogus
    expect_refused "no type" 1.2.3
    expect_refused "bad version" 1.2 patch
    expect_refused "no arguments"
}

for_each_shell run_suite
finish
