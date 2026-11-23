#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_next-action.sh - tests for next-action.sh (stubbed queue.sh, no network).
# usage: test_next-action.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${NEXT_ACTION_UNDER_TEST:-$SCRIPT_DIR/next-action.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

STUB_DIR="$TEST_TMP/stub"
mkdir -p "$STUB_DIR"
# Create the stub queue.sh: it records its arguments and prints STUB_DIR/queue.json.
# shellcheck disable=SC2016  # the text is a script for the stub, expanded when the stub runs
make_queue_stub() {
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$*" > "$STUB_DIR/queue-args"' 'cat "$STUB_DIR/queue.json"' > "$STUB_DIR/queue.sh"
    chmod +x "$STUB_DIR/queue.sh"
}
make_queue_stub
export STUB_DIR QUEUE_SCRIPT="$STUB_DIR/queue.sh"

# Build one issue: number, column, agent ("" = none), labels (comma list), blockers ("n:STATE,..."), open PRs (comma list).
issue() {
    jq -nc --argjson n "$1" --arg column "$2" --arg agent "$3" --arg labels "$4" --arg blockers "$5" --arg prs "$6" --arg closed "${7:-}" '
        {number: $n, column: $column, closedAt: (if $closed == "" then null else $closed end), agent: (if $agent == "" then null else $agent end),
         labels: ($labels | split(",") | map(select(. != ""))),
         openPrs: ($prs | split(",") | map(select(. != "") | tonumber)),
         blockedBy: ($blockers | split(",") | map(select(. != "") | split(":") | {number: (.[0] | tonumber), state: .[1]}))}'
}

# Write the board the stub queue.sh returns: the issues (JSON lines) as arguments; no argument = an empty board.
board() { jq -sc '{board: 12, issues: .}' < <(printf '%s\n' "$@" | grep -v '^$') > "$STUB_DIR/queue.json"; }

# Check the answer: a jq expression that must be true for the output.
answer_is() { check_that "$1" [ "$(jq -r "$2" <<<"$OUT")" = "true" ]; }

# Run the whole suite with the current shell.
run_suite() {
    board
    run_script
    check_that "an empty board is done" [ "$OUT" = '{"action":"done"}' ]
    check_that "it reads the five columns and Done in ONE call" [ "$(cat "$STUB_DIR/queue-args")" = "Triage Todo Doing Review Testing Done" ]

    board "$(issue 1 Triage "" "" "" "")"
    run_script
    answer_is "a new issue in Triage starts the triager" '.action == "run" and .agent == "triager"'
    answer_is "the triager takes the whole column (issue null)" '.issue == null'
    answer_is "and the issues it covers are listed" '.issues == [1]'

    board "$(issue 1 Triage "" "" "" "")" "$(issue 2 Triage "" needs-info "" "")" "$(issue 3 Triage "" "" "" "")"
    run_script
    answer_is "the triager's issues leave out the parked ones" '.issues == [1, 3]'

    board "$(issue 1 Triage "" needs-info "" "")"
    run_script
    answer_is "a needs-info issue in Triage is never started" '.action == "waiting"'
    answer_is "and it is listed as waiting for the user" '.issues[0].why | contains("needs-info")'

    board "$(issue 1 Todo "" "" "" "")"
    run_script
    answer_is "an issue in Todo starts the coder" '.agent == "coder" and .issue == 1'

    board "$(issue 1 Todo "" "" "2:OPEN" "")" "$(issue 2 Todo "" "" "" "")"
    run_script
    answer_is "an issue blocked by an open issue is skipped, the next ready one is taken" '.issue == 2'
    board "$(issue 1 Todo "" "" "2:CLOSED" "")"
    run_script
    answer_is "a closed blocker does not block" '.agent == "coder" and .issue == 1'
    board "$(issue 1 Todo "" "" "2:OPEN" "")"
    run_script
    answer_is "when everything in Todo is blocked it waits and names the blocker" '.action == "waiting" and (.issues[0].why | contains("#2"))'

    board "$(issue 5 Todo "" "" "" "")" "$(issue 6 Todo "" "" "" "")"
    run_script
    answer_is "the top of Todo (board order) is taken first" '.issue == 5'
    board "$(issue 5 Todo "" needs-info "" "")" "$(issue 6 Todo "" "" "" "")"
    run_script
    answer_is "a needs-info issue in Todo is skipped" '.issue == 6'

    board "$(issue 1 Review "" "" "" "30")"
    run_script
    answer_is "an issue in Review with an open PR starts the reviewer" '.agent == "reviewer" and .issue == 1'
    board "$(issue 1 Review "" "" "" "")"
    run_script
    answer_is "an issue in Review without a PR waits for the user" '.action == "waiting" and (.issues[0].why | contains("without an open pull request"))'

    board "$(issue 1 Testing "" "" "" "30")"
    run_script
    answer_is "an issue in Testing starts the tester" '.agent == "tester" and .issue == 1'
    board "$(issue 1 Review "" needs-info "" "30")"
    run_script
    answer_is "a needs-info issue in Review is never started, even with an open PR" '.action == "waiting"'
    board "$(issue 1 Testing "" needs-info "" "30")"
    run_script
    answer_is "a needs-info issue in Testing is never started" '.action == "waiting"'

    board "$(issue 1 Doing "Coder" "" "" "")"
    run_script
    answer_is "a claim resumes the agent named in the Agent field" '.agent == "coder" and .issue == 1'
    answer_is "and says it is a resume" '.reason | startswith("resume")'
    board "$(issue 1 Review "Reviewer" "" "" "30")"
    run_script
    answer_is "a claimed Reviewer resumes the reviewer" '.agent == "reviewer" and .issue == 1'
    board "$(issue 1 Testing "Tester" "" "" "")"
    run_script
    answer_is "a claimed Tester resumes the tester" '.agent == "tester"'
    board "$(issue 1 Triage "Triager" "" "" "")"
    run_script
    answer_is "a claimed Triager resumes the triager for the column (issue null)" '.agent == "triager" and .issue == null and .issues == [1]'
    board "$(issue 1 Doing "Coder" needs-info "" "")"
    run_script
    answer_is "an interrupted run is resumed even when the label is set" '.agent == "coder"'

    board "$(issue 1 Doing "" "" "" "")"
    run_script
    answer_is "an issue in Doing without a claim goes to the coder" '.agent == "coder" and .issue == 1'
    board "$(issue 1 Doing "" needs-info "" "")"
    run_script
    answer_is "a parked issue in Doing without a claim waits for the user" '.action == "waiting"'

    # The order: a claim, Doing, Triage, Testing, Review, Todo.
    board "$(issue 1 Todo "" "" "" "")" "$(issue 2 Review "" "" "" "30")" "$(issue 3 Testing "" "" "" "30")" "$(issue 4 Triage "" "" "" "")" "$(issue 5 Doing "" "" "" "")" "$(issue 6 Review "Reviewer" "" "" "31")"
    run_script
    answer_is "a claim comes first" '.issue == 6 and .agent == "reviewer"'
    board "$(issue 1 Todo "" "" "" "")" "$(issue 2 Review "" "" "" "30")" "$(issue 3 Testing "" "" "" "30")" "$(issue 4 Triage "" "" "" "")" "$(issue 5 Doing "" "" "" "")"
    run_script
    answer_is "then an issue in Doing" '.issue == 5 and .agent == "coder"'
    board "$(issue 1 Todo "" "" "" "")" "$(issue 2 Review "" "" "" "30")" "$(issue 3 Testing "" "" "" "30")" "$(issue 4 Triage "" "" "" "")"
    run_script
    answer_is "then Triage" '.agent == "triager"'
    board "$(issue 1 Todo "" "" "" "")" "$(issue 2 Review "" "" "" "30")" "$(issue 3 Testing "" "" "" "30")"
    run_script
    answer_is "then Testing" '.issue == 3 and .agent == "tester"'
    board "$(issue 1 Todo "" "" "" "")" "$(issue 2 Review "" "" "" "30")"
    run_script
    answer_is "then Review" '.issue == 2 and .agent == "reviewer"'
    board "$(issue 1 Todo "" "" "" "")"
    run_script
    answer_is "then Todo" '.issue == 1 and .agent == "coder"'

    board "$(issue 1 Triage "" needs-info "" "")" "$(issue 2 Todo "" "" "1:OPEN" "")"
    run_script
    answer_is "everything left waits for the user: both are listed" '.action == "waiting" and (.issues | length) == 2'

    # The archive action: Done holds an issue closed before the current month (today is injected), nothing else can run.
    export NEXT_ACTION_TODAY=2026-11-23
    board "$(issue 1 Done "" "" "" "" 2026-10-31T23:59:59Z)"
    run_script
    answer_is "an issue of Done closed in an earlier month asks for the archive (no agent)" '.action == "archive" and (.reason | length) > 0 and (has("agent") | not)'
    board "$(issue 1 Done "" "" "" "" 2026-11-01T00:00:00Z)"
    run_script
    answer_is "Done issues of the current month alone are all done, not archived" '.action == "done"'
    board "$(issue 1 Done "" "" "" "" 2025-11-30T00:00:00Z)"
    run_script
    answer_is "a previous year counts as an earlier month" '.action == "archive"'
    board "$(issue 1 Done "" "" "" "" 2026-11-05T00:00:00Z)" "$(issue 2 Todo "" "" "3:OPEN" "")"
    run_script
    answer_is "Done issues of the current month do not hide the waiting issues" '.action == "waiting" and (.issues | length) == 1'
    board "$(issue 1 Done "" "" "" "" 2026-10-05T00:00:00Z)" "$(issue 2 Todo "" "" "" "")"
    run_script
    answer_is "an agent row comes before the archive" '.action == "run" and .agent == "coder"'
    board "$(issue 1 Done "" "" "" "" 2026-10-05T00:00:00Z)" "$(issue 2 Todo "" "" "3:OPEN" "")"
    run_script
    answer_is "the archive comes before waiting" '.action == "archive"'
    board "$(issue 1 Done "" "" "" "" 2026-10-05T00:00:00Z)" "$(issue 2 Todo "" needs-info "" "")"
    run_script
    answer_is "the archive comes before waiting for a parked issue too" '.action == "archive"'
    board "$(issue 1 Done "" "" "" "" 2026-10-05T00:00:00Z)" "$(issue 2 Done-2026-09 "" "" "" "" 2026-09-05T00:00:00Z)"
    run_script
    answer_is "an issue in an archive column is not Done: not listed as waiting, not archived again" '.action == "archive"'
    board "$(issue 2 Done-2026-09 "" "" "" "" 2026-09-05T00:00:00Z)"
    run_script
    answer_is "only archive columns left: all done" '.action == "done"'
    unset NEXT_ACTION_TODAY

    printf '%s\n' '{"board": null, "issues": []}' > "$STUB_DIR/queue.json"
    run_script
    answer_is "without a board it says so and starts nothing" '.action == "no-board" and (has("agent") | not)'

    run_script extra
    check_that "an argument is a usage error" [ "$RC" -eq 1 ]
    run_script --help
    check_that "--help prints the usage and exits 0" [ "$RC" -eq 0 ]
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ERROR: board unreachable" >&2' 'exit 1' > "$STUB_DIR/queue.sh"
    run_script
    check_that "an error of the board read stops it with an error, nothing is dispatched" [ "$RC" -ne 0 ]
    check_that "and no action is printed" [ -z "$(jq -r '.action? // empty' <<<"$OUT" 2>/dev/null)" ]
    make_queue_stub
}

for_each_shell run_suite
finish
