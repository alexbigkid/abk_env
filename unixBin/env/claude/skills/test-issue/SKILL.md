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

## 1. Pick the issue

The user may name one. Otherwise take the first issue in Testing that is not waiting for a human:

```bash
$Q Testing | jq -r '[.issues[] | select(.labels | index("needs-info") | not)] | first | .number // empty'
$B claim Tester <n>
$S <n>          # pr, branch, base, headSha, mergeable
```

`"pr": null`: nothing to merge, `$B release <n>` and report.

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
- `1` anything else (head moved: test the new head again from step 2; `CONFLICTING`: failure path, the coder must rebase).

## 4. QA

If the repo has `docs/agents/qa-testing.md`, follow it now (deploy to QA, test the frontend against the backend or the other way round). If it does not exist, skip this step and say in the result comment that QA testing was skipped because nothing is defined.

## 5. Result

**Passed**: `$B move <n> Done "End date:=today"` and post a comment: what you tested, the merge commit, QA done or skipped.

**Failed**: post a comment with exactly what failed (criterion, check or command), the output, and how to reproduce it; then `$B move <n> Todo` and `$B order <n>` so it comes first.
- Before the merge the PR is still open and the coder continues on its branch.
- After the merge (a QA failure) the PR is merged and the issue is closed by it: `gh issue reopen <n>`. The fix goes in a **new** PR: the comment says so and names the merged PR and the merge commit; the coder starts a new branch `{Type}/<n>/<short-name>-fix`.

## 6. Park for the user

Only a human can help (a criterion that cannot be judged, an environment you have no access to, missing information): do not merge. Park the issue as the project-board skill describes (`needs-info`, a comment saying what is needed, `$B move <n> Triage`) and remove the worktree.

## No board

The board commands print `SKIPPED`; test and merge the issue the user names. Skip the column move and `End date`, and post the result (passed, or failed with details) as a comment on the issue.

## Stop and report

For technical failures (an API error, a refused merge) stop, report, release your claim (`$B release <n>`) and leave the issue in Testing. Report: issue, PR, what was tested, the merge commit with `verified`, QA done or skipped, and the decision (Done, Todo or parked).
