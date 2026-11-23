---
name: test-issue
description: Test the pull request of an issue in the Testing column, merge it with a GitHub-signed squash merge when the checks are green, then move the issue to Done with End date or back to Todo with the failure details. Use when the tester should verify, merge and finish an issue.
---

# Test issue

Testing → Done, or back to Todo. You verify, merge and close. You never write code, commit, sign or push: GitHub signs the squash merge, so you need no key.

```bash
Q=~/.claude/skills/prioritize/scripts/queue.sh
B=~/.claude/skills/project-board/scripts/board.sh
S=~/.claude/skills/review/scripts/review-state.sh
W=~/.claude/skills/review/scripts/review-worktree.sh
M=~/.claude/skills/test-issue/scripts/merge-pr.sh
H=~/.claude/skills/code-issue/scripts/with-https.sh     # git over HTTPS: no SSH, no YubiKey
```

In a headless run (the orchestrator) write the literal paths instead of these variables.

## 1. Pick the issue

The user may name one. Otherwise take the first issue in Testing that is not waiting for a human:

```bash
$Q Testing | jq -r '[.issues[] | select(.labels | index("needs-info") | not)] | first | .number // empty'
$B claim Tester <n>
$S <n>          # pr, branch, base, headSha, mergeable
```

`"pr": null`: look whether the PR was merged already (`gh issue view <n> --json closedByPullRequestsReferences`; of the PRs listed take the newest one with `gh pr view <pr> --json state,mergeCommit`). It is MERGED (by you in an earlier run whose board move failed, or by someone else): do not test again, go to step 4 and 5 with that PR and its `mergeCommit` sha. The newest one closed unmerged: treat it as no PR. No PR at all: `$B release <n>` and report.

## 2. Test

```bash
$H git fetch origin <branch>
dir=$($W add <branch>)                  # throwaway worktree: never touch the user's checkout
sha=$(git -C "$dir" rev-parse HEAD)     # the commit you test; the merge is pinned to it
```

Go through every acceptance criterion of the issue (`gh issue view <n>`) against the PR and run what can run locally in the worktree: the repo's tests and linters, and the scripts the PR adds. Note for each criterion what you ran and saw. Remove the worktree when done, also when you stop early: `$W remove "$dir"`.

A criterion you cannot judge, or an environment you cannot reach: park the issue (step 6) instead of guessing.

## 3. Merge

Only when every criterion is met:

```bash
$M <n> --commit "$sha" --dry-run        # all the guards, no merge
$M <n> --commit "$sha"                  # squash merge, prints: merged: <sha> verified=true
```

The script merges only when the PR head is still `$sha`, the PR is `MERGEABLE` and the required checks are green (all checks, when none is marked required). Never merge another way and never use "rebase and merge" (it drops the signatures). Exit codes:

- `2` a check failed: the failure path (step 5), name the checks.
- `3` checks still running: stop and report, leave the issue in Testing, `$B release <n>`; run again later. Do not wait in a loop.
- `4` merged but not verified: report it to the user, then go on.
- `1` anything else (head moved: test the new head again from step 2; `CONFLICTING`: failure path, the coder must rebase; too many checks to judge: park, a human must judge).

Remove the worktree after the merge and on every one of these exits (also in steps 5 and 6).

## 4. QA

After the merge, when the repo defines it: `docs/agents/qa-testing.md` lists per component (for example backend, frontend) how the merged code reaches QA and how to tell it has arrived (a version endpoint, a deploy job), the integration test command, the QA addresses, and which components depend on which. Backend integration tests call the API, so they test backend and API together; frontend integration tests run against the QA backend. The coder writes them with the code (see `code-issue`); you only run them.

1. The components the PR changed (from its file paths) and the components that depend on them are the ones to test: a backend change runs the backend API tests **and** the integration tests of the frontends that use it, a frontend change runs its own.
2. Wait until the merge commit is deployed to QA, as the file says (a few checks, no endless loop). Not deployed in time: `$B release <n>`, stop and report; the issue stays in Testing and the next run does steps 4 and 5 for the merged PR.
3. Run the integration tests those components define. Any failure: the failure path in step 5.
4. No qa-testing.md, or no integration tests defined for the affected components: skip and say so in the result comment ("QA skipped: nothing defined"). That is not an error.

## 5. Result

**Passed**: `$B move <n> Done "End date=today"` (`=`, so a second Done after a reopen replaces the old date) and post a comment: what you tested, the merge commit, QA run (which tests) or skipped. If the move fails after the merge, retry it; if it still fails, report that the PR is merged and the board move is missing, the next run finishes it (step 1).

**Failed**: post a comment with exactly what failed (criterion, check or command), the output, and how to reproduce it; then `$B move <n> Todo` and `$B order <n>` so it comes first.
- Before the merge the PR is still open and the coder continues on its branch.
- After the merge (a QA failure) the PR is merged and the issue is closed by it: `gh issue reopen <n>`. The fix goes in a **new** PR: the comment says so and names the merged PR and the merge commit; the coder starts a new branch `{Type}/<n>/<short-name>-fix`.

## 6. Park for the user

Only a human can help (a criterion that cannot be judged, an environment you have no access to, missing information): do not merge. Park the issue as the project-board skill describes (`needs-info`, a comment saying what is needed, `$B move <n> Triage`) and remove the worktree.

## No board

Step 1 finds nothing without a board (`$Q` has no columns): work on the issue the user names. The board commands print `SKIPPED`. Skip the column move and `End date`, and post the result (passed, or failed with details) as a comment on the issue.

## Stop and report

For technical failures (an API error, a refused merge) stop, report, release your claim (`$B release <n>`) and leave the issue in Testing. Report: issue, PR, what was tested, the merge commit with `verified`, QA done or skipped, and the decision (Done, Todo or parked).
