#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_abkLib.sh - tests for the install retry and failed-package functions of abkLib.sh.
#
# Self-contained: stub commands count their calls in a temp dir, no network, no installs.
# abkLib.sh is bash only, so every case runs in /bin/bash.
#
# usage: test_abkLib.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
RUNNER=bash

# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/env/claude/skills/project-board/scripts/testing-lib.sh"
handle_test_help "$@"

# Run a snippet in bash with abkLib.sh loaded and no waiting between retries; sets OUT and RC.
run_lib() {
    OUT=$(cd "$REPO_DIR" && ABK_RETRY_WAIT=0 INSTALLED_DIR="$TEST_TMP/pkgs" /bin/bash -c ". ./unixBin/abkLib.sh >/dev/null 2>&1; $1" 2>&1)
    RC=$?
}

# Stub that fails the first N calls (N = $1), then succeeds; counts its calls in $TEST_TMP/count.
make_flaky_stub() {
    rm -f "$TEST_TMP/count"
    cat > "$TEST_TMP/flaky.sh" <<STUB
#!/usr/bin/env bash
echo x >> "$TEST_TMP/count"
[ "\$(wc -l < "$TEST_TMP/count")" -gt $1 ]
STUB
    chmod +x "$TEST_TMP/flaky.sh"
}

calls() { wc -l < "$TEST_TMP/count" | tr -d ' '; }

make_flaky_stub 0
run_lib "AbkLib_RunWithRetry '$TEST_TMP/flaky.sh'"
check_that "success: rc 0" [ "$RC" -eq 0 ]
check_that "success: runs once" [ "$(calls)" = 1 ]

make_flaky_stub 2
run_lib "AbkLib_RunWithRetry '$TEST_TMP/flaky.sh'"
check_that "transient failure: rc 0 after two retries" [ "$RC" -eq 0 ]
check_that "transient failure: three calls" [ "$(calls)" = 3 ]

make_flaky_stub 99
run_lib "AbkLib_RunWithRetry '$TEST_TMP/flaky.sh'"
check_that "deterministic failure: rc not 0" [ "$RC" -ne 0 ]
check_that "deterministic failure: not more than three calls" [ "$(calls)" = 3 ]

run_lib "AbkLib_RunWithRetry 'exit 7'"
check_that "failure keeps the exit code" [ "$RC" -eq 7 ]

run_lib "AbkLib_ListFailedItems tools_x.json"
check_that "no failure recorded: empty list" [ -z "$OUT" ]

run_lib "AbkLib_RecordFailedItem tools_x.json serverless; AbkLib_RecordFailedItem tools_x.json adobe-dng-converter; AbkLib_ListFailedItems tools_x.json"
check_that "recorded failures are listed by name" [ "$OUT" = "serverless adobe-dng-converter" ]

run_lib "AbkLib_RecordFailedItem tools_x.json a; AbkLib_ClearFailedItems tools_x.json; AbkLib_ListFailedItems tools_x.json"
check_that "cleared list is empty" [ -z "$OUT" ]

finish
