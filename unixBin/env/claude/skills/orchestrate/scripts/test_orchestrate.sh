#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_orchestrate.sh - tests for orchestrate.sh (stubbed claude, state machine, park script; no network).
# usage: test_orchestrate.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${ORCHESTRATE_UNDER_TEST:-$SCRIPT_DIR/orchestrate.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

STUB_DIR="$TEST_TMP/stub"
mkdir -p "$STUB_DIR/actions"

# Create the stubs: the state machine (prints actions/<n>.json for the n-th call, then done), claude (logs its
# arguments, exit code from claude-rc), the park script and the review state (capped from the file capped).
# shellcheck disable=SC2016  # the texts are scripts for the stubs, expanded when they run
make_stubs() {
    printf '%s\n' '#!/usr/bin/env bash' 'n=$(cat "$STUB_DIR/calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/calls"' \
        '[ -f "$STUB_DIR/next-fails" ] && { echo "ERROR: board unreachable" >&2; exit 1; }' \
        'if [ -f "$STUB_DIR/actions/$n.json" ]; then cat "$STUB_DIR/actions/$n.json"; else echo "{\"action\":\"done\"}"; fi' > "$STUB_DIR/next-action.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$STUB_DIR/claude.log"' 'exit "$(cat "$STUB_DIR/claude-rc" 2>/dev/null || echo 0)"' > "$STUB_DIR/claude"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "park %s | %s\n" "$1" "$2" >> "$STUB_DIR/park.log"' > "$STUB_DIR/park.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "{\"capped\": $(cat "$STUB_DIR/capped" 2>/dev/null || echo false), \"headReviewed\": $(cat "$STUB_DIR/head-reviewed" 2>/dev/null || echo false)}"' > "$STUB_DIR/review-state.sh"
    chmod +x "$STUB_DIR/next-action.sh" "$STUB_DIR/claude" "$STUB_DIR/park.sh" "$STUB_DIR/review-state.sh"
}
make_stubs
printf '%s\n' "coder: Read, Edit, Bash(~/.claude/skills/x/run.sh:*), Bash(gh issue view:*)" "reviewer: Read" "tester: Read" "triager: Read, Grep" > "$STUB_DIR/allowed.conf"
export STUB_DIR NEXT_ACTION_SCRIPT="$STUB_DIR/next-action.sh" CLAUDE_BIN="$STUB_DIR/claude" PARK_SCRIPT="$STUB_DIR/park.sh" \
    REVIEW_STATE_SCRIPT="$STUB_DIR/review-state.sh" ORCHESTRATE_ALLOWED_TOOLS="$STUB_DIR/allowed.conf" \
    ORCHESTRATE_LOCK_DIR="$TEST_TMP/lock" GH_REPO="o/r"

# Reset the stubs: no actions, no logs, claude succeeds, nothing capped, no lock.
reset_stubs() {
    rm -f "$STUB_DIR"/actions/*.json "$STUB_DIR/calls" "$STUB_DIR/claude.log" "$STUB_DIR/park.log" "$STUB_DIR/next-fails" "$STUB_DIR/claude-rc" "$STUB_DIR/capped" "$STUB_DIR/head-reviewed"
    rm -f "$TEST_TMP/lock/pid"; rmdir "$TEST_TMP/lock" 2>/dev/null
    return 0
}

# Set the answer of the n-th decision of the state machine: n, agent, issue ("null" for none), reason, and optional issues JSON.
act() { jq -nc --arg a "$2" --argjson i "$3" --arg r "$4" --argjson is "${5:-null}" '{action: "run", agent: $a, issue: $i, reason: $r} + (if $is == null then {} else {issues: $is} end)' > "$STUB_DIR/actions/$1.json"; }

# Count the lines of a log file (0 when it does not exist).
lines_of() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

# Run the whole suite with the current shell.
run_suite() {
    reset_stubs
    run_script
    check_that "nothing to do: exit 0" [ "$RC" -eq 0 ]
    check_that "it says all is done" grep -q "all done" <<<"$OUT"
    check_that "no agent was started" [ ! -f "$STUB_DIR/claude.log" ]

    reset_stubs
    act 1 triager null "new issues in Triage" '[4]'
    act 2 coder 12 "top of Todo, blockers closed"
    run_script
    check_that "a sequence of actions runs to the end" [ "$RC" -eq 0 ]
    check_that "both agents were started, one after the other, in order" [ "$(lines_of "$STUB_DIR/claude.log")" = "2" ]
    check_that "the first run is the triager" grep -q -- "--agent triager" <(sed -n 1p "$STUB_DIR/claude.log")
    check_that "the second run is the coder" grep -q -- "--agent coder" <(sed -n 2p "$STUB_DIR/claude.log")
    check_that "the run is headless (-p)" grep -q -- "^-p " "$STUB_DIR/claude.log"
    check_that "the prompt names the issue" grep -q "#12" <(sed -n 2p "$STUB_DIR/claude.log")
    check_that "the allowlist of the agent is passed, comma separated (an entry may contain spaces)" grep -q -- "--allowedTools Read, Edit, .*Bash(gh issue view:\*) " <(sed -n 2p "$STUB_DIR/claude.log")
    check_that "a ~/ script path is allowed in the literal form" grep -q -- "Bash(~/.claude/skills/x/run.sh:\*)" <(sed -n 2p "$STUB_DIR/claude.log")
    check_that "and in the expanded home form (what the permission check sees when a variable holds the path)" grep -q -- "Bash($HOME/.claude/skills/x/run.sh:\*)" <(sed -n 2p "$STUB_DIR/claude.log")
    check_that "each run has a budget cap" grep -q -- "--max-budget-usd 5" "$STUB_DIR/claude.log"
    check_that "the lock is released at the end" [ ! -d "$TEST_TMP/lock" ]

    reset_stubs
    echo '{"action":"waiting","issues":[{"number":9,"why":"needs your answer (needs-info)"}]}' > "$STUB_DIR/actions/1.json"
    run_script
    check_that "waiting for the user: exit 0" [ "$RC" -eq 0 ]
    check_that "it lists what waits" grep -q "#9: needs your answer" <<<"$OUT"
    check_that "nothing was started" [ ! -f "$STUB_DIR/claude.log" ]

    reset_stubs
    echo '{"action":"no-board","reason":"no columns"}' > "$STUB_DIR/actions/1.json"
    run_script
    check_that "no board: reports it and exits 0" [ "$RC" -eq 0 ] 
    check_that "no board: nothing was started" [ ! -f "$STUB_DIR/claude.log" ]

    reset_stubs
    act 1 coder 12 "top of Todo"
    run_script --dry-run
    check_that "--dry-run prints the action" grep -q '"agent":"coder"' <<<"$OUT"
    check_that "--dry-run starts nothing" [ ! -f "$STUB_DIR/claude.log" ]
    check_that "--dry-run takes no lock" [ ! -d "$TEST_TMP/lock" ]

    reset_stubs
    act 1 coder 12 "top of Todo"
    act 2 reviewer 12 "in Review"
    run_script --once
    check_that "--once does one dispatch" [ "$(lines_of "$STUB_DIR/claude.log")" = "1" ]
    check_that "--once exits 0" [ "$RC" -eq 0 ]

    reset_stubs
    act 1 coder 12 "top of Todo"
    act 2 reviewer 12 "in Review"
    echo 1 > "$STUB_DIR/claude-rc"
    run_script
    check_that "a failed agent run stops with exit 2" [ "$RC" -eq 2 ]
    check_that "it says which agent and issue and that the claim stays" grep -q "agent coder failed.*#12.*claim stays" <<<"$OUT"
    check_that "nothing else was started after the failure" [ "$(lines_of "$STUB_DIR/claude.log")" = "1" ]
    check_that "the failure does not park the issue" [ ! -f "$STUB_DIR/park.log" ]
    check_that "the lock is released after a failure" [ ! -d "$TEST_TMP/lock" ]

    reset_stubs
    act 1 coder 12 "top of Todo"
    act 2 coder 12 "top of Todo"
    run_script
    check_that "the same action twice in a row parks the issue" grep -q "^park 12 | " "$STUB_DIR/park.log"
    check_that "the reason names the agent" grep -q "coder" "$STUB_DIR/park.log"
    check_that "the agent ran only once (not a second time)" [ "$(lines_of "$STUB_DIR/claude.log")" = "1" ]
    check_that "and the loop went on afterwards (exit 0)" [ "$RC" -eq 0 ]

    reset_stubs
    act 1 triager null "new issues in Triage" '[4,5]'
    act 2 triager null "new issues in Triage" '[4,5]'
    run_script
    check_that "a triager without progress parks every issue it covers" [ "$(lines_of "$STUB_DIR/park.log")" = "2" ]
    check_that "both issues are named" grep -q "^park 5 | " "$STUB_DIR/park.log"

    reset_stubs
    act 1 coder 12 "top of Todo"
    act 2 coder 12 "resume: claimed by Coder"
    run_script
    check_that "a different action for the same issue is progress, not parked" [ ! -f "$STUB_DIR/park.log" ]
    check_that "so both ran" [ "$(lines_of "$STUB_DIR/claude.log")" = "2" ]

    reset_stubs
    act 1 reviewer 12 "in Review"
    echo true > "$STUB_DIR/capped"
    run_script
    check_that "a review at the round cap is parked" grep -q "^park 12 | .*round cap" "$STUB_DIR/park.log"
    check_that "and the reviewer is not started" [ ! -f "$STUB_DIR/claude.log" ]
    reset_stubs
    act 1 reviewer 12 "resume: claimed by Reviewer"
    echo true > "$STUB_DIR/capped"
    echo true > "$STUB_DIR/head-reviewed"
    run_script
    check_that "at the cap with the last review already posted only the move is missing: the reviewer runs, nothing is parked" [ "$(lines_of "$STUB_DIR/claude.log")" = "1" ]
    check_that "(not parked)" [ ! -f "$STUB_DIR/park.log" ]
    reset_stubs
    act 1 reviewer 12 "in Review"
    echo false > "$STUB_DIR/capped"
    run_script
    check_that "a review below the cap runs the reviewer" [ "$(lines_of "$STUB_DIR/claude.log")" = "1" ]
    reset_stubs
    act 1 coder 12 "top of Todo"
    echo true > "$STUB_DIR/capped"
    run_script
    check_that "the round cap concerns the reviewer only: the coder still runs" [ "$(lines_of "$STUB_DIR/claude.log")" = "1" ]
    check_that "and nothing is parked for it" [ ! -f "$STUB_DIR/park.log" ]

    reset_stubs
    mkdir -p "$TEST_TMP/lock"
    echo $$ > "$TEST_TMP/lock/pid"
    act 1 coder 12 "top of Todo"
    run_script
    check_that "a running orchestrator blocks a second one" [ "$RC" -eq 1 ]
    check_that "it says so" grep -q "another orchestrator is running" <<<"$OUT"
    check_that "nothing was started" [ ! -f "$STUB_DIR/claude.log" ]
    check_that "the lock of the other one is left alone" [ -f "$TEST_TMP/lock/pid" ]
    echo 999999 > "$TEST_TMP/lock/pid"
    run_script
    check_that "the lock of a dead orchestrator is taken over" [ "$RC" -eq 0 ]
    check_that "and the agent ran" [ "$(lines_of "$STUB_DIR/claude.log")" = "1" ]

    reset_stubs
    act 1 coder 1 "a"
    act 2 coder 2 "b"
    act 3 coder 3 "c"
    ORCHESTRATE_MAX_DISPATCHES=2 run_script
    check_that "the dispatch limit stops with exit 3" [ "$RC" -eq 3 ]
    check_that "after exactly the allowed runs" [ "$(lines_of "$STUB_DIR/claude.log")" = "2" ]

    reset_stubs
    touch "$STUB_DIR/next-fails"
    run_script
    check_that "a failing board read stops with an error" [ "$RC" -eq 1 ]
    check_that "and starts nothing" [ ! -f "$STUB_DIR/claude.log" ]

    reset_stubs
    act 1 unknown 1 "x"
    run_script
    check_that "an agent without an allowlist is an error" [ "$RC" -ne 0 ]
    check_that "and is not started" [ ! -f "$STUB_DIR/claude.log" ]

    check_that "the real allowlist file has a line for every agent" [ "$(grep -c -E '^(triager|coder|reviewer|tester): ' "$SCRIPT_DIR/allowed-tools.conf")" = "4" ]

    run_script extra
    check_that "an unknown argument is a usage error" [ "$RC" -eq 1 ]
    run_script --help
    check_that "--help prints the usage and exits 0" [ "$RC" -eq 0 ]
}

for_each_shell run_suite
finish
