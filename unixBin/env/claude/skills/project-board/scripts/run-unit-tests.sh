#!/usr/bin/env bash

#------------------------------------------------------------------------------
# run-unit-tests.sh - run every skill unit test file (skills/*/scripts/test_*.sh) with bash.
# usage: run-unit-tests.sh [skills_dir]     (default: the skills dir this script is in)
# Prints one line per file (passed, failed) and a total; the output of a failing file follows
# its line. Exit code 0 only when every file passes and at least one was found.
# Only unit tests (stubs, no network). The install tests at the repo root are not run here.
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)

case "${1:-}" in
    --help|-h) sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

SKILLS_DIR=${1:-$SCRIPT_DIR/../..}
if [ ! -d "$SKILLS_DIR" ]; then
    echo "error: not a directory: $SKILLS_DIR" >&2
    exit 1
fi
# With the default dir the tests of the scripts in unixBin (unixBin/test_*.sh) run too.
EXTRA_DIR=""
if [ -z "${1:-}" ]; then EXTRA_DIR="$SKILLS_DIR/../../.."; fi

files=0
total_passed=0
total_failed=0
any_failed=0

while read -r test_file; do
    files=$((files + 1))
    name=$(basename "$test_file")
    output=$(/bin/bash "$test_file" 2>&1)
    rc=$?
    # A file may run once per shell, so it has several "== N passed, M failed" lines: sum them.
    summary=$(grep -E '^== [0-9]+ passed, [0-9]+ failed' <<< "$output")
    if [ -z "$summary" ]; then
        printf '%-40s error (exit %s, no summary line)\n' "$name" "$rc"
        echo "$output"
        any_failed=1
        continue
    fi
    passed=0
    failed=0
    while read -r _ p _ f _; do
        passed=$((passed + p))
        failed=$((failed + ${f%,}))
    done <<< "${summary//,/}"
    total_passed=$((total_passed + passed))
    total_failed=$((total_failed + failed))
    printf '%-40s %s passed  %s failed\n' "$name" "$passed" "$failed"
    if [ "$rc" -ne 0 ] || [ "$failed" -ne 0 ]; then
        echo "$output"
        any_failed=1
    fi
done < <({
    find "$SKILLS_DIR" -path '*/scripts/test_*.sh' -type f
    if [ -n "$EXTRA_DIR" ]; then find "$EXTRA_DIR" -maxdepth 1 -name 'test_*.sh' -type f; fi
} | sort)

if [ "$files" -eq 0 ]; then
    echo "error: no test file found in $SKILLS_DIR" >&2
    exit 1
fi

printf '%-40s %s files  %s passed  %s failed\n' "total" "$files" "$total_passed" "$total_failed"
[ "$any_failed" -eq 0 ]
