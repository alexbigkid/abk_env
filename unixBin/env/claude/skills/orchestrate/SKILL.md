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
| 6 | no agent row applies and `Done` holds an issue closed before the current month (UTC) | `archive-done.sh` (no agent); the driver then decides again; a failing script stops it (exit 2), the same archive action twice in a row stops it with an error |
| 7 | nothing | stop: all Done, or the rest waits for you |

`needs-info` issues are never started. Without a board it prints `no-board` and starts nothing.

## Guards

- **Lock**: a second orchestrator refuses to start; do not run agents by hand meanwhile.
- **Permissions**: each agent gets only the tools listed for it in `scripts/allowed-tools.conf`; widen that file when an agent reports a denied command. No agent may run an interpreter (`bash`, `zsh`, `sh`), so `bash -c '...'` is refused. The unit tests run through the literal path of `run-unit-tests.sh`; for the reviewer and tester the driver adds `Bash(<worktree root>/*)` at run time (the root is the physical path that `review-worktree.sh add` also prints, so the rule matches), and they run the worktree's own copy of the script with no argument, so the tests of the pull request, also those in `unixBin`, run. Probes (attended, `claude -p --model haiku`): `run-unit-tests.sh` by its literal path runs; `bash -c` and `zsh -c` are refused; a single test file by its literal path is refused, so it has no entry of its own and the agents run the whole (fast) suite. A real orchestrator run of a small issue through coder, reviewer and tester is still pending. Not covered: the allowed tools (`git`, `gh`, `jq`, the scripts) still act with the user's credentials, so the list is not a sandbox (issue #9).
- **Headless commands**: the permission check of a headless run refuses a command that sets or expands a shell variable (`X=...`, `~` or `$HOME` in an assignment, `$(...)`) and a heredoc that contains JSON; it runs a literal path with a text heredoc (verified with real probes). The driver therefore adds a note to every prompt: call scripts by their full literal path, write values literally, give review findings in the text form of `post-review.sh`.
- **Worktree directory**: a headless run refuses `cd` outside its session directories. Review worktrees are therefore created in one dedicated root (`review-worktree.sh root`) and the driver adds exactly that directory (`--add-dir`) for the reviewer and the tester.
- **Budget**: `ORCHESTRATE_BUDGET_USD` (default 1) per agent run (`--max-budget-usd`, notional API dollars (probe with a subscription login: the cap works, in notional dollars. With `--max-budget-usd 0.0001` the run stops, the JSON has `subtype: "error_max_budget_usd"`, `is_error: true`, `terminal_reason: "budget_exhausted"`, an empty `result`, and the exit code is 1, so the driver stops with exit 2 and prints that reason); `ORCHESTRATE_MAX_DISPATCHES` (default 50) per start.
- **No progress**: the same action twice in a row (the board did not change) parks the issue(s) with `scripts/park.sh` (label `needs-info`, a comment, back to Triage) instead of running it again.
- **Round cap**: a Review issue at `MAX_REVIEW_ROUNDS` is parked without starting the reviewer (`review-state.sh` reads the cap from its single definition).
- **Failure**: a failed agent run (no tokens, an error) stops everything with exit 2 and names the agent and issue. The claim stays; start the orchestrator again when you can, row 1 resumes it.

The orchestrator never edits code, commits or merges; the agents do, within their own rules.

## Model and usage

- **Model per agent**: an optional line `model-<agent>: <alias>` in `scripts/allowed-tools.conf` is passed as `--model <alias>`; no line means the default model. Triager and tester use `haiku`; coder and reviewer keep the default. Change the values in the file.
- **Usage per run**: the driver runs `claude -p --output-format json`, prints the agent's text (`result`), then one line: `usage: <agent> #<issue> <seconds>s in=<n> out=<n> cost=$<x>`. Only fields present in the JSON are shown; `cache=<n>` is `cache_creation_input_tokens` + `cache_read_input_tokens` (with prompt caching `input_tokens` alone is tiny and misleading), and an `is_error` run adds `error=<subtype>/<terminal_reason>`.
- **Probe of `claude -p --output-format json`** (run attended): top-level fields `result`, `is_error`, `subtype`, `terminal_reason`, `total_cost_usd`, `duration_ms`, `duration_api_ms`, `num_turns`, `usage` (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`), `modelUsage`, `permission_denials`, `session_id`. Model alias tested: `haiku` (works). `permission_denials` helps to tune the allowlist but is not printed yet. Each line is also appended, with a timestamp, to `~/.claude/orchestrate-usage.log` (`ORCHESTRATE_USAGE_LOG` changes it). Output that is not JSON is printed as is.

## Small steps

Use `orchestrate.sh --once`: one agent per start. Read its usage line (and `/usage` in an interactive session), then decide whether to start the next run.

## Tests

`scripts/test_next-action.sh`, `test_park.sh` and `test_orchestrate.sh` (stubbed `gh`, `claude` and state machine; run in CI).
