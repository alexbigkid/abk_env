---
name: code-issue
description: Take the top issue in the Todo column, implement it on a linked feature branch with signed commits, open a pull request and hand the issue to review; also address review comments on its pull request. Use when the coder should pick up or implement an issue end to end, or fix review feedback on a pull request.
---

# Code issue

Todo → Doing → Review. You write the code, make the signed commits, create the branch and the PR. You do **not** review, merge or close (reviewer and tester do). Follow `/dev-guidelines` (SOLID, KISS, no over-engineering), `/tdd` for the implementation and `/diagnose` for bugs.

```bash
Q=~/.claude/skills/prioritize/scripts/queue.sh
B=~/.claude/skills/project-board/scripts/board.sh
P=~/.claude/skills/code-issue/scripts/pr-feedback.sh
C=~/.claude/skills/code-issue/scripts/commit-push.sh
H=~/.claude/skills/code-issue/scripts/with-https.sh     # git over HTTPS: no SSH, no YubiKey
```

In a headless run (the orchestrator) write the literal paths instead of these variables.

## 1. Pick the issue

The user may name one; after an interrupted run (for example an API failure) the user names the issue again, it is still in Doing and claimed by Coder, so continue on its branch (`$H git fetch origin <branch> && git checkout <branch>`). Otherwise take the top Todo issue whose blockers are all closed and that is not waiting for a human (`needs-info`); review rework comes back at the top of Todo:

```bash
$Q | jq -r '[.issues[] | select(.column == "Todo" and (.labels | index("needs-info") | not) and all(.blockedBy[]; .state == "CLOSED"))] | first | .number // empty'
```

Nothing found: report that no issue is ready. Read the issue, its comments and any agent brief. If it has open points that block you (a human decision) or lacks information to implement it, park it (see Parking an issue in the project-board skill) instead of guessing. `$P <n>` tells whether it already has an open PR: then it is rework, go to step 6.

## 2. Start

```bash
$B move <n> Doing "Start date:=today"     # the date is only set when empty, so rework keeps it
$B claim Coder <n>
```

## 3. Branch

Type from the issue label: `bug` → B, `feature` or `enhancement` → F, `docs` → D, `research` → R, `test` → T. No label, or none of its labels maps (for example only `question`): infer the type from title and description and assign the matching label (`gh label create <label> --force` first if it is missing, then `gh issue edit <n> --add-label <label>`). Branch `{Type}/{n}/{short-name}` (kebab-case, at most 5 words; for an issue the tester reopened after a failed QA, whose first PR is merged: `{Type}/{n}/{short-name}-fix`), created and linked to the issue (`--base` is the default branch, usually `main`). If the branch already exists (an interrupted run), check it out instead of creating it:

```bash
$H gh issue develop <n> --name F/<n>/<short-name> --base main --checkout
```

## 4. Implement

Test first (`/tdd`), then the code; run the repo's tests and linters; update the docs the change touches. Keep to the acceptance criteria, no extras. A change to a backend or frontend component comes with integration tests for it (backend: through the API; frontend: against the backend), and `docs/agents/qa-testing.md` lists them so the tester runs them on QA.

## 5. Commit, push, PR, hand-off

Commit in small steps with `$C "<message>" --all` (all changes, untracked files included) or `$C "<message>" <file>...`. It signs with the coder key, pushes only `{Type}/{n}/{name}` branches over HTTPS and never force-pushes. It refuses staged files that look like secrets, an index you staged yourself and any commit that is on no remote ref yet and is not signed well (every commit of the branch when origin has no refs at all); it needs the one-time setup in [GIT-SETUP.md](GIT-SETUP.md) and is covered by `scripts/test_commit-push.sh` (run it after changing the script). If it refuses (missing config, unsigned, rejected, secrets), stop and report; never commit another way. Every git command that talks to GitHub (fetch, pull, clone) goes through `$H`; plain `git` would use your SSH remote and the YubiKey. Message style: look at `git log --oneline -10`; end with the Co-Authored-By line you were given.

```bash
gh pr create --base main --head <branch> --title "<title> (#<n>)" --body-file - <<'BODY'
Closes #<n>

## What
<what changed>
## Tested
<what you ran and saw>
## Not verified
<what you could not test; be honest>
BODY
$B move <n> Review          # clears your claim
```

## 6. Review feedback

The reviewer returns the issue to Todo with comments on the PR. `$P <n>` prints the open threads, PR comments and reviews. Check out the branch (`$H git fetch origin && git checkout <branch> && $H git pull`), then take **every** item. A run that was cut off may have done part of it: when `$P` lists nothing to handle, only the hand-off is missing (`$B move <n> Review`, step 5 was cut off after the PR was opened); an item that the branch already fixes (see `git log`) is answered `fixed in <sha>` without redoing it. The reviewer starts each comment with a tag; an untagged comment (for example from the user) counts as `[must-fix]`.

- `[must-fix]`: change the code in this PR; it cannot be deferred. If you think it is wrong, do not skip it: answer `disputed (<reason>)` in the summary below. A dispute goes to the user; do not wait for it in a loop.
- `[suggestion]`: you evaluate it and choose. Fix it now when it is cheap and in scope; or decline it with a reason when you judge it not worth doing (`declined`, the reviewer accepts that); or open a follow-up issue (see Follow-up issues) and give the reason. Every suggestion gets one of the three answers.

Commit and push with `$C`. Post one PR comment that starts with the line `Review items handled:`, ends with the line `<!-- abk:review-items-handled -->` (the hidden tag the scripts look for) and lists each item with `fixed in <sha>`, `declined (<reason>)`, `follow-up #<m> (<reason>)` or `disputed (<reason>)`; `$P` then lists only feedback newer than that comment. Then `$B move <n> Review`, also when a dispute is the only open item (it is listed in that comment for the reviewer and the user).

If the PR of the issue is already merged (a reopened issue) and your answers need no code change, there is nothing to review: post the summary, then hand the issue to the tester with `$B move <n> Testing`; it finishes the merged PR (step 1 of `test-issue`). Do not move it to Review: the reviewer needs an open PR.

A `[must-fix]` you are unable to fix (not one you think is wrong) is neither skipped nor guessed: park the issue for the user and report exactly what blocks you.

## Follow-up issues

For a review item you do not fix now, or work you found but must not do here, open a follow-up issue and place it in Triage; you never prioritize it and **you never start the triager** (or any agent): the triager runs in its own context when whoever orchestrates starts it.

- Body in the `/to-issues` template: `## What to build`, `## Acceptance criteria`, `## Blocked by`, and the line `Follow-up of #<n> (PR #<pr>)`. Name blockers in the text; the triager turns them into Relationships.
- If you cannot fill it in because information is missing, add the label `needs-info` (`gh label create needs-info --force` first if it does not exist) and list what is missing under `## Open questions`. The triager leaves such issues in Triage.
- `gh issue create ...`, then `$B add <issue>`. End your hand-over with the line `Triage needs a run: #<a> #<b>` (or `Triage: no new issues`).

## No board

The board commands print `SKIPPED` and exit 0; the branch, commits and PR work as usual. `$Q` has no `column` without a board, so step 1's query finds nothing: work on the issue the user names, and post a short hand-off comment on the issue (what you did, PR link, what is next). The handover is manual.

## Stop and report

Park the issue (see Parking an issue in the project-board skill) when only a human can help: missing information or a decision, a `[must-fix]` or tests you cannot make pass. For technical failures (missing signing config, a refused push, a failing board or API call) stop, report and leave the issue in Doing with your claim. Say what you did and what is left.
