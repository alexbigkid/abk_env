---
name: archive-done
description: Keep the Done column of the project board small by moving issues closed in an earlier month into archive columns Done-<year>-<month>, and collapsing the monthly columns of a past year into Done-<year>. Use when the Done column grows, at a month or year change, or when asked to archive done issues.
---

# Archive done

`scripts/archive-done.sh [--dry-run]` makes `Done` show only the current month (UTC).

```bash
~/.claude/skills/archive-done/scripts/archive-done.sh --dry-run   # print what would happen
~/.claude/skills/archive-done/scripts/archive-done.sh             # do it
```

Needs `gh` (scope `project`) and `jq`; the repo comes from the git remote `origin` or `GH_REPO`. `ARCHIVE_TODAY=YYYY-MM-DD` replaces the current UTC date (tests). The orchestrator integration is a separate issue; until then run it by hand.

## Rules

- A new month: every issue in `Done` closed before the first day of the current month moves to `Done-<year>-<month>` of its close month (`Done-2026-10`). The column is created when missing.
- A new year: issues of a past year go to `Done-<year>` (`Done-2026`); the monthly columns of that year are emptied and then removed.
- Order, newest first: `Done`, `Done-2027-02`, `Done-2027-01`, `Done-2026`, `Done-2025`. Other columns keep their place and are never touched.
- Date of an issue: GitHub `closedAt`, fallback `End date`. An issue in `Done` with neither stays where it is. Months and years are UTC.
- New columns: exactly this name (no emoji), color `GRAY`, empty description.
- Re-runnable: a second run changes nothing; after months without a run all missing columns are created and filled in one pass.
- No board: it prints `SKIPPED` and changes nothing.

## Safety rule

Columns are the options of the `Status` field. **Removing a column that still holds an issue clears the Status of every issue in it.** So each step is its own request, in this order:

1. update the option list (adds new columns),
2. move the issues (one request, aliases),
3. read the board again; stop with an error (nothing removed) when any issue changed its state, a moved issue is not in its new column, or a column to remove still holds an issue,
4. only then remove the empty monthly columns.

Every option update sends the **complete** list: each existing option with its `id`, `name`, `color`, `description` (empty string when none), new options without `id`, in the final column order.

## Spike result (attended, on a copy of the board)

- `updateProjectV2Field` with the complete option list keeps all existing ids; new options get ids; no issue loses its Status; the list order is the column order.
- `updateProjectV2ItemFieldValue` with `singleSelectOptionId` moves an issue into an archive column.
- Removing an empty option works and leaves all issues alone; removing an option that holds an issue leaves that issue with no Status.
- **Warning:** the built-in project workflow "close issue when Status is Done" closed a real issue on the copy. Anyone repeating the spike must switch the workflows off on the copy. On the real board the script reads the state of every issue back after the moves and reports a difference as an error. The first real run is attended.

## Tests

`scripts/test_archive-done.sh` runs the script against `scripts/gh-stub.sh`, a small simulator of the board (it also clears the Status of issues in a removed column, like GitHub). It covers month change, year change, catch-up, `End date` fallback, UTC at a month boundary, idempotence, other columns untouched, the complete option list in the request, the safety stop, a state change, paging, `--dry-run` and no board.
