#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_queue.sh - tests for queue.sh (stubbed gh, no network).
# usage: test_queue.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${QUEUE_UNDER_TEST:-$SCRIPT_DIR/queue.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

STUB_DIR="$TEST_TMP/stub"
mkdir -p "$STUB_DIR" "$TEST_TMP/bin"
# shellcheck disable=SC2016  # the text is a script for the stub, expanded when it runs
printf '%s\n' '#!/usr/bin/env bash' 'cat "$STUB_DIR/answer.json"' > "$TEST_TMP/bin/gh"
chmod +x "$TEST_TMP/bin/gh"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH"

# Build an issue: number, column ("" = none), agent ("" = none), labels (comma list), PRs ("n:STATE,..."), blockers ("n:STATE,...").
item() {
    jq -nc --argjson n "$1" --arg column "$2" --arg agent "$3" --arg labels "$4" --arg prs "$5" --arg blockers "$6" '
        {status: (if $column == "" then null else {name: $column} end),
         content: {number: $n, title: "t\($n)", state: "OPEN", body: "## Acceptance criteria", repository: {nameWithOwner: "o/r"},
           labels: {nodes: ($labels | split(",") | map(select(. != "") | {name: .}))},
           issueFieldValues: {nodes: ([{name: "P1", field: {name: "Other"}}] + (if $agent == "" then [] else [{name: $agent, field: {name: "Agent"}}] end))},
           closedByPullRequestsReferences: {nodes: ($prs | split(",") | map(select(. != "") | split(":") | {number: (.[0] | tonumber), state: .[1]}))},
           blockedBy: {nodes: ($blockers | split(",") | map(select(. != "") | split(":") | {number: (.[0] | tonumber), state: .[1], repository: {nameWithOwner: "o/r"}}))},
           blocking: {nodes: []}}}'
}

# Write the board answer with the given items (JSON lines as arguments).
board_with() {
    jq -sc '{data: {repository: {projectsV2: {nodes: [{id: "P", number: 12, items: {pageInfo: {hasNextPage: false, endCursor: null}, nodes: .}}]}}}}' < <(printf '%s\n' "$@") > "$STUB_DIR/answer.json"
}

# Check one field of one issue: check name, issue number, jq path, expected value.
field_is() { check_that "$1" [ "$(jq -c ".issues[] | select(.number == $2) | $3" <<<"$OUT")" = "$4" ]; }

# Run the whole suite with the current shell.
run_suite() {
    board_with "$(item 1 "🔍 Triage" "" "needs-info,bug" "" "")" "$(item 2 "🚧 Doing" "Coder" "" "" "")" \
        "$(item 3 "👀 Review" "" "" "30:OPEN,31:MERGED,32:CLOSED" "")" "$(item 4 "📋 Todo" "" "" "" "2:OPEN")" "$(item 5 "✅ Done" "" "" "" "")"
    run_script Triage Todo Doing Review Testing
    check_that "it succeeds" [ "$RC" -eq 0 ]
    field_is "the emoji of the column is stripped" 1 .column '"Triage"'
    field_is "labels are listed" 1 '.labels' '["needs-info","bug"]'
    field_is "the Agent field is the agent (the claim)" 2 .agent '"Coder"'
    field_is "an issue without the Agent field has agent null (another issue field does not count)" 1 .agent null
    field_is "only OPEN pull requests count" 3 .openPrs '[30]'
    field_is "an issue without pull requests has none" 1 .openPrs '[]'
    field_is "a blocker is reported with its state" 4 '.blockedBy[0].state' '"OPEN"'
    check_that "an issue in a column that was not asked for is left out" [ "$(jq '[.issues[] | select(.number == 5)] | length' <<<"$OUT")" = "0" ]
    check_that "the board number is reported" [ "$(jq .board <<<"$OUT")" = "12" ]
    check_that "the order is the order on the board" [ "$(jq -c '[.issues[].number]' <<<"$OUT")" = "[1,2,3,4]" ]

    run_script Review
    check_that "a single column can be asked for" [ "$(jq -c '[.issues[].number]' <<<"$OUT")" = "[3]" ]
    run_script
    check_that "the default is Triage and Todo" [ "$(jq -c '[.issues[].number]' <<<"$OUT")" = "[1,4]" ]

    echo '{"data":{"repository":{"projectsV2":{"nodes":[]},"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}' > "$STUB_DIR/answer.json"
    run_script
    check_that "without a board the board is null" [ "$(jq .board <<<"$OUT")" = "null" ]
    echo '{"data":{"repository":{"projectsV2":{"nodes":[{"id":"A","number":1,"items":{"pageInfo":{"hasNextPage":false},"nodes":[]}},{"id":"B","number":2,"items":{"pageInfo":{"hasNextPage":false},"nodes":[]}}]}}}}' > "$STUB_DIR/answer.json"
    run_script
    check_that "two linked boards are refused" [ "$RC" -ne 0 ]
    check_that "and the message says so" grep -q "2 linked project boards" <<<"$OUT"
    run_script --help
    check_that "--help prints the usage and exits 0" [ "$RC" -eq 0 ]
}

for_each_shell run_suite
finish
