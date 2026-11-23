#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_run-unit-tests.sh - tests for run-unit-tests.sh (stub test files, no network).
# usage: test_run-unit-tests.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${RUN_UNIT_TESTS_UNDER_TEST:-$SCRIPT_DIR/run-unit-tests.sh}
# shellcheck disable=SC1091
source "$SCRIPT_DIR/testing-lib.sh"
handle_test_help "$@"

SKILLS="$TEST_TMP/skills"

# Make a stub test file: skill, file name, exit code, the lines it prints after "stub output".
make_stub_test() {
    local skill=$1 file=$2 code=$3
    shift 3
    mkdir -p "$SKILLS/$skill/scripts"
    {
        printf '%s\n' '#!/usr/bin/env bash' "echo 'stub output of $file'"
        for line in "$@"; do printf '%s\n' "echo '$line'"; done
        printf '%s\n' "exit $code"
    } > "$SKILLS/$skill/scripts/$file"
}

# True when the output of the last run contains the extended regex.
out_has() { grep -Eq "$1" <<< "$OUT"; }

# Run the whole suite with the current shell.
run_suite() {
    rm -rf "$SKILLS"
    mkdir -p "$SKILLS"
    run_script "$SKILLS"
    check_that "no test file found is an error" [ "$RC" -ne 0 ]
    check_that "it says that no test file was found" out_has "no test file"

    make_stub_test one test_a.sh 0 "== 3 passed, 0 failed"
    make_stub_test two test_b.sh 0 "== 4 passed, 0 failed"
    make_stub_test one not_a_test.sh 1 "ran not_a_test"
    run_script "$SKILLS"
    check_that "all passing succeeds" [ "$RC" -eq 0 ]
    check_that "a line per file with passed and failed" out_has "test_a.sh +3 passed +0 failed"
    check_that "the second file is listed" out_has "test_b.sh +4 passed +0 failed"
    check_that "the total sums the files" out_has "total +2 files +7 passed +0 failed"
    check_that "a file that is not test_*.sh is not run" [ -z "$(grep not_a_test <<< "$OUT")" ]
    check_that "output of passing files is hidden" [ -z "$(grep 'stub output' <<< "$OUT")" ]

    make_stub_test two test_b.sh 1 "== 1 passed, 2 failed"
    run_script "$SKILLS"
    check_that "one failing file fails the run" [ "$RC" -ne 0 ]
    check_that "the failing file shows its counts" out_has "test_b.sh +1 passed +2 failed"
    check_that "the output of the failing file is shown" out_has "stub output of test_b.sh"
    check_that "the total counts the failures" out_has "total +2 files +4 passed +2 failed"

    make_stub_test two test_b.sh 2 "crashed before a summary"
    run_script "$SKILLS"
    check_that "a crash without a summary fails the run" [ "$RC" -ne 0 ]
    check_that "the crash is marked as an error" out_has "test_b.sh +error"

    make_stub_test two test_b.sh 0 "== 2 passed, 0 failed"
    make_stub_test one test_a.sh 0 "== 2 passed, 0 failed" "== 5 passed, 1 failed"
    run_script "$SKILLS"
    check_that "a file that runs several shells is summed" out_has "test_a.sh +7 passed +1 failed"
    check_that "a failed count fails the run even when the exit code is 0" [ "$RC" -ne 0 ]

    # No argument: the copy of the script in a repo-shaped tree also runs unixBin/test_*.sh; a directory argument does not.
    tree="$TEST_TMP/tree"
    rm -rf "$tree"
    mkdir -p "$tree/unixBin/env/claude/skills/project-board/scripts"
    cp "$SCRIPT_DIR/run-unit-tests.sh" "$tree/unixBin/env/claude/skills/project-board/scripts/"
    SKILLS="$tree/unixBin/env/claude/skills"
    make_stub_test one test_a.sh 0 "== 1 passed, 0 failed"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "== 2 passed, 0 failed"' > "$tree/unixBin/test_tool.sh"
    SCRIPT_UNDER_TEST="$tree/unixBin/env/claude/skills/project-board/scripts/run-unit-tests.sh"
    run_script
    check_that "no argument also runs unixBin/test_*.sh" out_has "test_tool.sh +2 passed +0 failed"
    run_script "$SKILLS"
    check_that "a directory argument runs only the skill tests" [ -z "$(grep test_tool <<< "$OUT")" ]
    SKILLS="$TEST_TMP/skills"
    SCRIPT_UNDER_TEST=${RUN_UNIT_TESTS_UNDER_TEST:-$SCRIPT_DIR/run-unit-tests.sh}

    run_script "$TEST_TMP/missing"
    check_that "a missing directory is an error" [ "$RC" -ne 0 ]
    run_script --help
    check_that "--help prints the usage and exits 0" [ "$RC" -eq 0 ]
}

check_that "run-unit-tests.sh is executable (agents and CI call it by path)" [ -x "$SCRIPT_DIR/run-unit-tests.sh" ]
check_that "test_run-unit-tests.sh is executable" [ -x "$SCRIPT_DIR/test_run-unit-tests.sh" ]

for_each_shell run_suite
finish
