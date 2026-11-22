---
name: project-board
description: Move GitHub issues between project board columns (Triage, Todo, Doing, Review, Testing, Done), set board fields (Priority, Size, Estimate, Start date, End date) and mark which agent works on an issue via the Agent issue field. Use when an issue-workflow agent (triager, coder, reviewer, tester) hands an issue over, claims it, or needs its board status.
---

# Project Board

One script, `scripts/board.sh`, does all board access for the workflow agents. Call it instead of writing `gh project ...` commands yourself. It resolves field and option ids at runtime, so it works on any board created from `board-template`.

## Commands

Run from inside the repo (or set `GH_REPO`). `<n>` is the issue number.

```bash
scripts/board.sh info <n>                       # board fields + current Agent
scripts/board.sh move <n> Doing                 # Triage | Todo | Doing | Review | Testing | Done
scripts/board.sh set <n> Priority P0            # Priority P0-P2, Size XS-XL, Estimate <number>
scripts/board.sh set <n> "Start date" today --if-empty
scripts/board.sh set <n> "End date" today
scripts/board.sh claim <n> Coder                # Triager | Coder | Reviewer | Tester
scripts/board.sh release <n>
scripts/board.sh add <n>                        # put issue on the board in Triage (needs PROJECT_NUMBER)
```

Names are case-insensitive; the emoji in the column names is not needed.

## Hand-off pattern

1. When you pick an issue up: `move` it to your column if needed, then `claim` it.
2. When you finish: `move` it to the next column. `move` always clears the Agent field, so an empty Agent means nobody is working on it.
3. Set board fields when your role owns them: triager sets Priority, Size, Estimate; coder sets Start date on first Doing (`--if-empty`, so rework keeps the original); tester sets End date on Done.

## No board

If the issue is on no project board, board commands print `SKIPPED: ...` and exit 0. This is not an error: do your own work, leave the issue where it is and post a short hand-off comment (what you did, which agent or step is next). The Agent field, relationships, branches, PRs and comments do not need a board and still work.

If the issue is on several boards, set `PROJECT_NUMBER` (see `docs/agents/project-board.md`).

## Errors

- `issue field 'Agent' not found`: create the single-select field Agent (Triager, Coder, Reviewer, Tester) under Settings > Issue fields.
- `Missing 'read:user' scope`: the user must run `gh auth refresh -h github.com -s read:user`.
- `option '...' not found`: the message lists the valid options.
