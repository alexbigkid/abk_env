#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_archive-done.sh - tests for archive-done.sh (stubbed gh = board simulator, no network).
# usage: test_archive-done.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${ARCHIVE_UNDER_TEST:-$SCRIPT_DIR/archive-done.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

STUB_DIR="$TEST_TMP/stub"
mkdir -p "$STUB_DIR" "$TEST_TMP/bin"
cp "$SCRIPT_DIR/gh-stub.sh" "$TEST_TMP/bin/gh"
chmod +x "$TEST_TMP/bin/gh"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH"

BASE_OPTIONS='[{"id":"o1","name":"Triage"},{"id":"o2","name":"Todo"},{"id":"o3","name":"Doing"},{"id":"o4","name":"Review"},{"id":"o5","name":"Testing"},{"id":"o6","name":"Done"}]'

# Give the Done column an emoji like the real board has (options and items).
emoji_done() {
    sed -i.bak 's/"Done"/"✅ Done"/g' "$STUB_DIR/board.json"
}

# Start a fresh board: extra archive options (JSON list of names) and the items (JSON list).
# An item is [item id, issue, status, closedAt, endDate].
new_board() {
    rm -f "$STUB_DIR/requests.log"
    unset STUB_STALE STUB_CLOSE STUB_NOBOARD STUB_PAGE
    jq -cn --argjson base "$BASE_OPTIONS" --argjson extra "$1" --argjson items "$2" '{
        options: ($base + [range(0; $extra | length) as $i | {id: "x\($i)", name: $extra[$i]}] | map({id, name, color: "GRAY", description: ""})),
        items: [$items[] | {id: .[0], issue: .[1], state: "CLOSED", status: .[2], closedAt: .[3], endDate: .[4]}]}' > "$STUB_DIR/board.json"
}

# Print the names of the columns, in order.
columns() { jq -r '[.options[].name] | join(",")' "$STUB_DIR/board.json"; }

# Print the column of an issue.
column_of() { jq -r --argjson n "$1" '.items[] | select(.issue == $n) | .status' "$STUB_DIR/board.json"; }

# Count the requests that change the board (column update or moves).
writes() { grep -c -e 'updateProjectV2' -e '^{"query"' "$STUB_DIR/requests.log" 2>/dev/null || true; }

# Run the whole suite with the current shell.
run_suite() {
    export ARCHIVE_TODAY=2026-11-15

    new_board '[]' '[["i1",1,"Done","2026-10-05T10:00:00Z",null],["i2",2,"Done","2026-11-02T10:00:00Z",null],["i3",3,"Todo","2026-01-02T10:00:00Z",null]]'
    emoji_done
    run_script
    check_that "month change succeeds" [ "$RC" -eq 0 ]
    check_that "the column of the closing month is created after Done" [ "$(columns)" = "Triage,Todo,Doing,Review,Testing,✅ Done,Done-2026-10" ]
    check_that "an issue of an earlier month moves into it" [ "$(column_of 1)" = "Done-2026-10" ]
    check_that "an issue of the current month stays in Done" [ "$(column_of 2)" = "✅ Done" ]
    check_that "another column is untouched, whatever its dates" [ "$(column_of 3)" = "Todo" ]
    check_that "the output tells what happened" grep -q "moved: #1" <<<"$OUT"
    check_that "the option update sends the existing ids and the new column without id" \
        jq -e '.variables.input.singleSelectOptions | (map(.id) | .[0:6]) == ["o1","o2","o3","o4","o5","o6"] and (.[6] | has("id") | not) and .[6].name == "Done-2026-10" and .[6].color == "GRAY" and .[6].description == ""' >/dev/null <<<"$(grep '^{"query"' "$STUB_DIR/requests.log" | head -1)"

    rm -f "$STUB_DIR/requests.log"
    run_script
    check_that "a second run changes nothing" [ "$(writes)" -eq 0 ]
    check_that "a second run says so" grep -q "nothing to archive" <<<"$OUT"

    new_board '[]' '[]'
    run_script
    check_that "an empty Done is a no-op" [ "$(writes)" -eq 0 ]

    ARCHIVE_TODAY=2026-12-03 new_board '[]' '[["i1",1,"Done","2026-09-30T08:00:00Z",null],["i2",2,"Done","2026-10-31T08:00:00Z",null],["i3",3,"Done","2026-11-20T08:00:00Z",null],["i4",4,"Done","2026-12-01T08:00:00Z",null]]'
    ARCHIVE_TODAY=2026-12-03 run_script
    check_that "several missed months are caught up, newest first" [ "$(columns)" = "Triage,Todo,Doing,Review,Testing,Done,Done-2026-11,Done-2026-10,Done-2026-09" ]
    check_that "each issue lands in its month" [ "$(column_of 1) $(column_of 2) $(column_of 3) $(column_of 4)" = "Done-2026-09 Done-2026-10 Done-2026-11 Done" ]

    new_board '[]' '[["i1",1,"Done",null,"2026-10-20"]]'
    run_script
    check_that "an issue without a close date uses End date" [ "$(column_of 1)" = "Done-2026-10" ]

    ARCHIVE_TODAY=2026-11-01 new_board '[]' '[["i1",1,"Done","2026-10-31T23:30:00Z",null],["i2",2,"Done","2026-11-01T00:00:00Z",null]]'
    ARCHIVE_TODAY=2026-11-01 run_script
    check_that "UTC: 23:30Z on the last day belongs to the old month" [ "$(column_of 1)" = "Done-2026-10" ]
    check_that "UTC: 00:00Z on the first day belongs to the new month" [ "$(column_of 2)" = "Done" ]

    new_board '["Done-2026-10","Done-2026-09"]' '[["i1",1,"Done-2026-10","2026-10-05T10:00:00Z",null],["i2",2,"Done-2026-09","2026-09-05T10:00:00Z",null],["i3",3,"Done","2026-12-20T10:00:00Z",null],["i4",4,"Done","2027-01-02T10:00:00Z",null]]'
    ARCHIVE_TODAY=2027-01-05 run_script
    check_that "year change succeeds" [ "$RC" -eq 0 ]
    check_that "the monthly columns collapse into the year column" [ "$(columns)" = "Triage,Todo,Doing,Review,Testing,Done,Done-2026" ]
    check_that "all issues of the old year are in it" [ "$(column_of 1) $(column_of 2) $(column_of 3)" = "Done-2026 Done-2026 Done-2026" ]
    check_that "an issue of the new year stays in Done" [ "$(column_of 4)" = "Done" ]
    check_that "the output tells about the removed columns" grep -q "removed column: Done-2026-10" <<<"$OUT"

    new_board '["Done-2026-10","Done-2025"]' '[["i1",1,"Done-2026-10","2026-10-05T10:00:00Z",null]]'
    ARCHIVE_TODAY=2027-01-05 run_script
    check_that "newest year first among the year columns" [ "$(columns)" = "Triage,Todo,Doing,Review,Testing,Done,Done-2026,Done-2025" ]

    new_board '["Done-2026-10"]' '[["i1",1,"Done-2026-10","2026-10-05T10:00:00Z",null]]'
    export STUB_STALE=1
    ARCHIVE_TODAY=2027-01-05 run_script
    check_that "a column that still holds an issue stops the script with an error" [ "$RC" -ne 0 ]
    check_that "the column is not removed" grep -q "Done-2026-10" <<<"$(columns)"
    check_that "the issue keeps its Status" [ "$(column_of 1)" = "Done-2026-10" ]
    check_that "the error says why" grep -q "still holds 1 issue" <<<"$OUT"
    unset STUB_STALE

    new_board '[]' '[["i1",1,"Done","2026-10-05T10:00:00Z",null]]'
    export STUB_CLOSE=1
    run_script
    check_that "a changed issue state is an error" [ "$RC" -ne 0 ]
    check_that "the error names the issue" grep -q "#1 changed its state" <<<"$OUT"
    unset STUB_CLOSE

    new_board '[]' '[["i1",1,"Done","2026-10-05T10:00:00Z",null],["i2",2,"Done","2026-09-05T10:00:00Z",null],["i3",3,"Done","2026-10-06T10:00:00Z",null],["i4",4,"Done","2026-11-06T10:00:00Z",null],["i5",5,"Done","2026-09-06T10:00:00Z",null]]'
    export STUB_PAGE=2
    run_script
    check_that "items on several pages are all read" [ "$(column_of 5) $(column_of 3)" = "Done-2026-09 Done-2026-10" ]
    unset STUB_PAGE

    new_board '[]' '[["i1",1,"Done","2026-10-05T10:00:00Z",null]]'
    cp "$STUB_DIR/board.json" "$TEST_TMP/before.json"
    run_script --dry-run
    check_that "--dry-run succeeds" [ "$RC" -eq 0 ]
    check_that "--dry-run changes nothing" cmp -s "$STUB_DIR/board.json" "$TEST_TMP/before.json"
    check_that "--dry-run sends no change request" [ "$(writes)" -eq 0 ]
    check_that "--dry-run tells the plan" grep -q "would move: #1 Done -> Done-2026-10" <<<"$OUT"

    export STUB_NOBOARD=1
    run_script
    check_that "without a board it reports SKIPPED" grep -q "^SKIPPED" <<<"$OUT"
    check_that "without a board it succeeds" [ "$RC" -eq 0 ]
    unset STUB_NOBOARD

    run_script --bogus
    check_that "an unknown option is a usage error" [ "$RC" -eq 1 ]
    ARCHIVE_TODAY=yesterday run_script
    check_that "a bad ARCHIVE_TODAY is refused" [ "$RC" -ne 0 ]
    run_script --help
    check_that "--help prints the usage and exits 0" [ "$RC" -eq 0 ]
}

for_each_shell run_suite
finish
