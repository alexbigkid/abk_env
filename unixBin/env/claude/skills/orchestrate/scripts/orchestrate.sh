#!/usr/bin/env bash

#------------------------------------------------------------------------------
# orchestrate.sh - run the issue workflow: ask the state machine what is next, run that ONE agent
# headless, repeat until nothing is left that does not need the user.
# Needs: gh, jq, claude. Run inside the repo (or set GH_REPO). Costs no tokens itself.
#------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/lib.sh"

NEXT_ACTION=${NEXT_ACTION_SCRIPT:-$SCRIPT_DIR/next-action.sh}
PARK=${PARK_SCRIPT:-$SCRIPT_DIR/park.sh}
REVIEW_STATE=${REVIEW_STATE_SCRIPT:-$SCRIPT_DIR/../../review/scripts/review-state.sh}
CLAUDE_BIN=${CLAUDE_BIN:-claude}
ALLOWED_TOOLS_FILE=${ORCHESTRATE_ALLOWED_TOOLS:-$SCRIPT_DIR/allowed-tools.conf}
LOCK_DIR=${ORCHESTRATE_LOCK_DIR:-${TMPDIR:-/tmp}/abk-orchestrate.lock}
BUDGET_USD=${ORCHESTRATE_BUDGET_USD:-5}
MAX_DISPATCHES=${ORCHESTRATE_MAX_DISPATCHES:-50}
# Appended to every prompt. Verified with real headless probes: the permission check refuses a command that sets a variable
# (X=..., X=~/..., $(...)) and a heredoc that contains JSON ({" ), but runs a literal path with a text heredoc.
HEADLESS_NOTE="This is a headless run and its permission check refuses a command that sets or expands a shell variable or uses \$(...), and a heredoc that contains JSON. So call the scripts by their full literal path (~/.claude/skills/<skill>/scripts/<script>), write every value (issue number, commit, directory) out literally in each command, and give the findings of a review to post-review.sh in the text form of its usage, not as JSON."
EXIT_AGENT_FAILED=2
EXIT_LIMIT=3

usage() {
    cat <<USAGE
usage: orchestrate.sh [--once] [--dry-run]
Loop: next-action.sh says what runs next, that ONE agent runs headless (claude -p --agent <name>) and
the loop asks again, until everything is Done or waits for you. One agent at a time, one board read per decision.
  --dry-run  print the next action and stop, start nothing
  --once     do one dispatch and stop
Guards: a lock (only one orchestrator), the allowlist of each agent ($(basename "$ALLOWED_TOOLS_FILE")), a budget cap per run
(\$ORCHESTRATE_BUDGET_USD, default $BUDGET_USD), at most \$ORCHESTRATE_MAX_DISPATCHES dispatches per start (default $MAX_DISPATCHES).
The same action twice in a row (no progress) parks the issue for you instead of running it again.
A review that reached the round cap is parked without starting the reviewer (unless its last review is posted and only the move is missing).
A failed agent run (no tokens, an error) stops everything with exit $EXIT_AGENT_FAILED: the claim stays, start it again to resume.
Exit codes: 0 all done, waiting for you, or --once/--dry-run finished; 1 error; $EXIT_AGENT_FAILED agent failed; $EXIT_LIMIT dispatch limit.
USAGE
}

# Take the lock: only one orchestrator at a time (a lock of a dead process is taken over).
take_lock() {
    local pid
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then die "another orchestrator is running (pid $pid)"; fi
        rm -f "$LOCK_DIR/pid"
        rmdir "$LOCK_DIR"
        mkdir "$LOCK_DIR" || die "cannot take the lock $LOCK_DIR"
    fi
    echo $$ > "$LOCK_DIR/pid"
    trap release_lock EXIT
}

# Release the lock.
release_lock() { rm -f "$LOCK_DIR/pid"; rmdir "$LOCK_DIR" 2>/dev/null || true; }

# Print the allowlist of an agent (the line after "<agent>: " in the allowlist file), comma separated.
allowed_tools() {
    local line
    line=$(grep "^$1: " "$ALLOWED_TOOLS_FILE" || true)
    [ -n "$line" ] || die "no allowlist for agent '$1' in $ALLOWED_TOOLS_FILE"
    # The agents call the scripts through a variable (B=~/.claude/...; $B ...): the permission check then matches only the
    # expanded home path, so every Bash(~/...) entry is allowed in both forms (awk, so no character of $HOME is special).
    printf '%s\n' "${line#"$1": }" | awk -v home="$HOME" '{
        n = split($0, entry, ", "); out = ""
        for (i = 1; i <= n; i++) {
            out = out (i > 1 ? "," : "") entry[i]
            if (substr(entry[i], 1, 7) == "Bash(~/") out = out ",Bash(" home "/" substr(entry[i], 8)
        }
        print out }'
}

# Park the issues of an action for the user, with the reason as comment.
park_issues() {
    local number
    for number in $(jq -r '[.issue // empty] + (.issues // []) | unique | .[]' <<<"$1"); do
        "$PARK" "$number" "$2"
    done
}

# Print the prompt for an action.
prompt_for() {
    local agent issue
    agent=$(jq -r .agent <<<"$1")
    issue=$(jq -r '.issue // empty' <<<"$1")
    if [ -z "$issue" ]; then
        echo "Triage the issues that wait in the Triage column ($(jq -r '.issues | map("#\(.)") | join(" ")' <<<"$1")). Follow your skill and report. $HEADLESS_NOTE"
    else
        echo "Work on issue #$issue ($(jq -r .reason <<<"$1")). Follow your skill and report. You are the $agent. $HEADLESS_NOTE"
    fi
}

once=""
dry_run=""
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --once) once=1 ;;
        --dry-run) dry_run=1 ;;
        *) usage_error ;;
    esac
    shift
done

[ -n "$dry_run" ] || take_lock
previous=""
dispatches=0
while :; do
    action=$("$NEXT_ACTION") || die "the state machine failed, nothing was started"
    case "$(jq -r .action <<<"$action")" in
        done) echo "all done: nothing is left on the board"; exit 0 ;;
        waiting) echo "nothing can run; waiting for you:"; jq -r '.issues[] | "  #\(.number): \(.why)"' <<<"$action"; exit 0 ;;
        no-board) jq -r '"no board: \(.reason)"' <<<"$action"; exit 0 ;;
        run) ;;
        *) die "unexpected answer of the state machine: $action" ;;
    esac
    if [ -n "$dry_run" ]; then printf '%s\n' "$action"; exit 0; fi

    if [ "$action" = "$previous" ]; then
        echo "no progress: the same action twice, parking: $action"
        park_issues "$action" "The orchestrator started the same action twice in a row and the board did not change ($(jq -r '"\(.agent): \(.reason)"' <<<"$action")). Please look at it; remove the label when it can go on."
        previous=""
        continue
    fi
    agent=$(jq -r .agent <<<"$action")
    issue=$(jq -r '.issue // empty' <<<"$action")
    if [ "$agent" = "reviewer" ] && [ "$("$REVIEW_STATE" "$issue" | jq -r '(.capped // false) and ((.headReviewed // false) | not)')" = "true" ]; then
        echo "review round cap reached for #$issue, parking"
        park_issues "$action" "The review round cap was reached without an agreement. The open review items are in the pull request. Please decide; remove the label when it can go on."
        previous=""
        continue
    fi
    tools=$(allowed_tools "$agent")
    dispatches=$((dispatches + 1))
    if [ "$dispatches" -gt "$MAX_DISPATCHES" ]; then echo "dispatch limit ($MAX_DISPATCHES) reached, stopping" >&2; exit "$EXIT_LIMIT"; fi
    previous=$action

    echo "== run $dispatches: $agent ${issue:+#$issue }($(jq -r .reason <<<"$action"))"
    agent_rc=0
    "$CLAUDE_BIN" -p "$(prompt_for "$action")" --agent "$agent" --allowedTools "$tools" --max-budget-usd "$BUDGET_USD" || agent_rc=$?
    if [ "$agent_rc" -ne 0 ]; then
        echo "agent $agent failed (exit $agent_rc) on ${issue:+#$issue}${issue:-its column}; its claim stays; start the orchestrator again to resume" >&2
        exit "$EXIT_AGENT_FAILED"
    fi
    if [ -n "$once" ]; then exit 0; fi
done
