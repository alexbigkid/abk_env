# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the test scripts that source this file

#------------------------------------------------------------------------------
# testing-lib.sh - small test harness shared by the test_*.sh scripts of the skills.
# Sourced, not executed. Provides: check, check_that, run_script, for_each_shell, finish, handle_test_help
# and a throwaway temp dir (TEST_TMP, removed on exit; set TEST_CLEANUP_HOOK to a function name to run
# something before the removal). The stub gh for the review tests is in review/scripts/review-stub-lib.sh.
# NOTE: check_that takes ONE condition. Never chain with && (the chained part is not counted);
# test_testing-lib.sh fails on such lines.
#------------------------------------------------------------------------------

PASSED=0
FAILED=0
OUT=""
RC=0
RUNNER=""

MAX_TMP_PATH_LENGTH=60
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/skill-test.XXXXXX")
if [ "${#TEST_TMP}" -gt "$MAX_TMP_PATH_LENGTH" ]; then   # gpg-agent sockets need a short path
    rmdir "$TEST_TMP"
    TEST_TMP=$(mktemp -d "/tmp/skill-test.XXXXXX")
fi

# Run the cleanup hook of the test script, then remove the temp dir (only a dir this harness created).
cleanup() {
    if [ -n "${TEST_CLEANUP_HOOK:-}" ]; then "$TEST_CLEANUP_HOOK"; fi
    case "$TEST_TMP" in
        */skill-test.*) [ -d "$TEST_TMP" ] && rm -rf "$TEST_TMP" ;;
    esac
}
trap cleanup EXIT

# Record the result of one check: the name and the exit code of the test expression.
check() {
    if [ "$2" -eq 0 ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        echo "FAIL [$RUNNER] $1"
        echo "      output: $OUT"
    fi
}

# Print the usage and stop when the first argument is --help; any other argument is a usage error.
handle_test_help() {
    case "${1:-}" in
        --help|-h) echo "usage: $(basename "$0")      runs the tests; exit code 0 = all passed"; exit 0 ;;
        "") ;;
        *) echo "usage: $(basename "$0")" >&2; exit 1 ;;
    esac
}

# Check a condition given as a command (for example: check_that "name" [ -z "$x" ]).
check_that() {
    local name=$1
    shift
    "$@"
    check "$name" $?
}

# Run the script under test with the current shell and the given arguments; sets OUT and RC. Stdin passes through.
run_script() {
    OUT=$("$RUNNER" "$SCRIPT_UNDER_TEST" "$@" 2>&1)
    RC=$?
}

# Call the function given as argument once for every distinct shell found among /bin/bash, bash and zsh.
for_each_shell() {
    local candidate resolved seen duplicate seen_shells=()
    for candidate in /bin/bash bash zsh; do
        resolved=$(command -v "$candidate" 2>/dev/null) || continue
        duplicate=""
        for seen in ${seen_shells[@]+"${seen_shells[@]}"}; do
            if [ "$resolved" -ef "$seen" ]; then duplicate=1; fi
        done
        [ -z "$duplicate" ] || continue
        seen_shells+=("$resolved")
        RUNNER=$resolved
        echo "== running with: $RUNNER"
        "$1"
    done
}

# Print the summary and return the exit code of the test script.
finish() {
    echo "== $PASSED passed, $FAILED failed"
    [ "$FAILED" -eq 0 ]
}
