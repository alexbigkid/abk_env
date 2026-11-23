#!/usr/bin/env bash

#------------------------------------------------------------------------------
# next-action.sh - the state machine of the issue workflow: print the next action as JSON.
# Needs: gh (scopes: repo, project), jq. One read of the board (queue.sh), no loops over issues.
#------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
QUEUE_SCRIPT=${QUEUE_SCRIPT:-$SCRIPT_DIR/../../prioritize/scripts/queue.sh}
BOARD_COLUMNS=(Triage Todo Doing Review Testing)
LABEL_PARKED="needs-info"

usage() {
    cat <<USAGE
usage: next-action.sh
Reads the board once and prints what runs next, as one JSON object:
  {"action": "run", "agent": "triager|coder|reviewer|tester", "issue": <number or null>, "reason": "..."}
                         (the triager has no issue; "issues" lists the ones in its column or claimed by it)
  {"action": "waiting", "issues": [{"number", "why"}]}   nothing can run, these wait for you
  {"action": "done"}                                     no open issue is left on the board
  {"action": "no-board", "reason": "..."}                the repo has no board: the columns are the state
The first row that has work wins (one agent runs at a time):
  1. an issue with the Agent field set (an interrupted run): the agent named there resumes it
  1b. an issue in Doing without a claim: coder
  2. issues in Triage without $LABEL_PARKED: triager (issue is null, it takes the whole column)
  3. an issue in Testing: tester
  4. an issue in Review with an open pull request: reviewer
  5. the top issue in Todo whose blockers are all closed: coder
Issues with $LABEL_PARKED are never started (except an interrupted run, row 1). Repo from the current directory or GH_REPO.
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -eq 0 ] || { usage >&2; exit 1; }

queue=$("$QUEUE_SCRIPT" "${BOARD_COLUMNS[@]}")
jq -c --arg parked "$LABEL_PARKED" '
    def run($agent; $issue; $reason): {action: "run", agent: $agent, issue: $issue, reason: $reason};
    def is_parked: .labels | index($parked);
    def open_blockers: [.blockedBy[] | select(.state != "CLOSED") | .number];
    def triager_issues($q): [$q.issues[] | select(.agent == "Triager" or (.column == "Triage" and (is_parked | not))) | .number];
    def first_in($column): [.issues[] | select(.column == $column and (is_parked | not))] | first;
    . as $q
    | if $q.board == null then {action: "no-board", reason: "without a board the columns are missing; name the issue and the agent yourself"}
      else
        ([$q.issues[] | select(.agent != null)] | first) as $claimed
        | ([$q.issues[] | select(.column == "Doing" and (is_parked | not))] | first) as $doing
        | ($q | first_in("Triage")) as $triage
        | ($q | first_in("Testing")) as $testing
        | ([$q.issues[] | select(.column == "Review" and (is_parked | not) and (.openPrs | length) > 0)] | first) as $review
        | ([$q.issues[] | select(.column == "Todo" and (is_parked | not) and (open_blockers | length) == 0)] | first) as $todo
        | if $claimed != null then
            (run($claimed.agent | ascii_downcase; (if $claimed.agent == "Triager" then null else $claimed.number end); "resume: claimed by \($claimed.agent)")
             + (if $claimed.agent == "Triager" then {issues: triager_issues($q)} else {} end))
          elif $doing != null then run("coder"; $doing.number; "resume: in Doing without a claim")
          elif $triage != null then (run("triager"; null; "new issues in Triage") + {issues: triager_issues($q)})
          elif $testing != null then run("tester"; $testing.number; "in Testing")
          elif $review != null then run("reviewer"; $review.number; "in Review with an open pull request")
          elif $todo != null then run("coder"; $todo.number; "top of Todo, blockers closed")
          elif ($q.issues | length) == 0 then {action: "done"}
          else {action: "waiting", issues: [$q.issues[] | {number, why:
                  (if is_parked then "needs your answer (\($parked))"
                   elif .column == "Review" then "in Review without an open pull request"
                   elif .column == "Todo" then "blocked by \(open_blockers | map("#\(.)") | join(", "))"
                   else "in \(.column)" end)}]}
          end
      end' <<<"$queue"
