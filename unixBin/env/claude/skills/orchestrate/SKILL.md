---
name: orchestrate
description: Run the issue workflow from Triage to Done by starting the right agent for the board state, one at a time, until everything is Done or waits for the user. Use when the user wants the triager, coder, reviewer and tester to run in turn without starting each by hand, or to find out what runs next.
---

# Orchestrate

The orchestrator is a script, not an agent: it costs no tokens itself. It reads the board (one read), picks the next agent, runs it headless (`claude -p --agent <name>`), waits for it to exit and decides again. **One agent runs at a time.** The board columns and the `Agent` field are the whole state, so a restart resumes.

```bash
O=~/.claude/skills/orchestrate/scripts
$O/next-action.sh              # what runs next, as JSON; changes nothing
$O/orchestrate.sh --dry-run    # the same through the driver
$O/orchestrate.sh --once       # one dispatch, then stop
$O/orchestrate.sh              # until everything is Done or waits for you
```

## What runs next

The first row that has work wins:

| # | Board state | Agent |
|---|---|---|
| 1 | an issue with the `Agent` field set (an interrupted run); in Doing without a claim | the agent named there; coder |
| 2 | new issues in Triage (not `needs-info`) | triager |
| 3 | Testing | tester |
| 4 | Review with an open pull request | reviewer |
| 5 | top of Todo, all blockers closed (rework is at the top) | coder |
| 6 | nothing | stop: all Done, or the rest waits for you |

`needs-info` issues are never started. Without a board it prints `no-board` and starts nothing.

## Guards

- **Lock**: a second orchestrator refuses to start; do not run agents by hand meanwhile.
- **Permissions**: each agent gets only the tools listed for it in `scripts/allowed-tools.conf`; widen that file when an agent reports a denied command.
- **Budget**: `ORCHESTRATE_BUDGET_USD` (default 5) per agent run; `ORCHESTRATE_MAX_DISPATCHES` (default 50) per start.
- **No progress**: the same action twice in a row (the board did not change) parks the issue(s) with `scripts/park.sh` (label `needs-info`, a comment, back to Triage) instead of running it again.
- **Round cap**: a Review issue at `MAX_REVIEW_ROUNDS` is parked without starting the reviewer (`review-state.sh` reads the cap from its single definition).
- **Failure**: a failed agent run (no tokens, an error) stops everything with exit 2 and names the agent and issue. The claim stays; start the orchestrator again when you can, row 1 resumes it.

The orchestrator never edits code, commits or merges; the agents do, within their own rules.

## Tests

`scripts/test_next-action.sh`, `test_park.sh` and `test_orchestrate.sh` (stubbed `gh`, `claude` and state machine; run in CI).
