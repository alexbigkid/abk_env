# PR mode (the reviewer agent)

Review the pull request of an issue that is in the **Review** column: the same three axes (Standards, Spec, Quality) as in [SKILL.md](SKILL.md), but the result is **one review on the PR** with tagged findings and a board move. You never change code, commit, merge or close anything.

```bash
Q=~/.claude/skills/prioritize/scripts/queue.sh
B=~/.claude/skills/project-board/scripts/board.sh
S=~/.claude/skills/review/scripts/review-state.sh
P=~/.claude/skills/review/scripts/post-review.sh
W=~/.claude/skills/review/scripts/review-worktree.sh
H=~/.claude/skills/code-issue/scripts/with-https.sh     # git over HTTPS: no SSH, no YubiKey
```

In a headless run (the orchestrator) write the literal paths instead of these variables.

## 1. Pick the issue and read its state

The user may name an issue (always without a board). With a board take the first issue in Review that is not waiting for a human:

```bash
$Q Review | jq -r '[.issues[] | select(.labels | index("needs-info") | not)] | first | .number // empty'
$B claim Reviewer <n>
$S <n>          # pr, branch, base, headSha, mergeable, round, max, capped, handledComment, handledIsNew, unresolvedThreads
```

`headReviewed: true`: your review of this very commit is already posted, the coder has not answered it, and an earlier run was cut off before the move. Do not review again (and do not claim a new round): read the counts in the title of your last review (`gh pr view <pr> --json reviews --jq '[.reviews[] | select(.body | contains("<!-- abk:review-round -->"))] | last | .body' | head -1`, "`<n> must-fix, <m> suggestion`") and go to step 5: `<n>` above 0 is the first bullet, otherwise the second.

Note the `round` and keep it; you pass it back when you post. `"pr": null`: no open PR, `$B release <n>` and report. `capped: true`: go straight to step 6, do not review. The cap `MAX_REVIEW_ROUNDS` is defined once in `scripts/review-lib.sh`; never write the number elsewhere. The claim is the lock between two reviewers; the pins in step 4 catch the rest.

## 2. Read the PR without touching the user's checkout

```bash
$H git fetch origin <branch> <base>
dir=$($W add <branch>)                    # detached throwaway worktree: read files and run tests/linters there
sha=$(git -C "$dir" rev-parse HEAD)       # the commit you review; you pin it in step 4
git diff origin/<base>...origin/<branch>  # the change; commits: git log origin/<base>..origin/<branch> --oneline
```

Always remove the worktree when you are done, also when you stop early or fail: `$W remove "$dir"`. After a crash, `$W prune` removes leftover review worktrees and empty temp dirs; run it only when no other reviewer is working, because it removes every review worktree.

## 3. Review

Standards, Spec and Quality as in SKILL.md (sources of standards, the issue as spec: `gh issue view <n>`, the Quality criteria from `dev-guidelines`). Without the Agent tool do the three axes yourself, one after the other, and keep them separate; with it you may run them as parallel sub-agents. Run the repo's linters in the worktree and all unit tests with `<worktree>/unixBin/env/claude/skills/project-board/scripts/run-unit-tests.sh` (the worktree's own copy, its path written out literally, **no argument**: with no argument the tests in `unixBin/test_*.sh` run too, with a directory argument they do not; it tests the PR code, not your checkout; never a self-made loop). Never run integration tests: the tester does, on QA. `mergeable: CONFLICTING` is a `[must-fix]` (the PR conflicts with its base). GitHub computes it lazily; `review-state.sh` already reads again twice while it is `UNKNOWN`. If it is still `UNKNOWN`, say so in your summary and do not claim there are no conflicts.

**Round 2 or later** (`round > 0`): verify what the coder did.
- `handledIsNew: true`: read `handledComment` (the coder's `Review items handled:` summary, `pr-feedback.sh` hides it) and the unresolved threads, and check each item.
- `handledIsNew: false` (no comment since your last review, the coder gave no answer): ignore the old comment; every earlier `[must-fix]` is open unless the code shows it fixed.
- A `[must-fix]` must be really fixed in the code.
- A `[suggestion]` is settled when the coder fixed it, declined it (`declined (<reason>)`, accepted as given) or deferred it to a follow-up issue that exists and has acceptance criteria (`gh issue view <m>`). A deferral without such an issue is re-marked `[must-fix]`.
- `disputed (<reason>)` on a must-fix: do not argue it again, go to step 6.

**Classify every finding**, no untagged ones:
- `[must-fix]`: the acceptance criteria are not met, a bug, a security problem, a broken or missing test for the change, or a hard standard violation.
- `[suggestion]`: style, an alternative design, optional hardening, extra tests beyond the scope.
- **Quality findings** are `[suggestion]` by default. They are `[must-fix]` only for clear waste (for example quadratic work over data that grows, one API call per item where one batched call is possible) or a change that is untestable by design. The Quality sub-agent marks each finding `clear` or `judgement call`: `clear` becomes `[must-fix]`, `judgement call` becomes `[suggestion]`.
- **Concurrency advice** (multi-threading, multiprocessing) only where the gain is real; otherwise do not mention it.

## 4. Post one review

```bash
$P <n> --round <round> --commit "$sha" <<'FINDINGS'
## Standards
...
## Spec
...
## Quality
...
@must-fix scripts/a.sh:12
the text of the finding, any number of lines
@suggestion
a finding without a location
FINDINGS
```

The text before the first `@` line is the summary; a finding starts with `@must-fix <file>:<line>` (or `@suggestion`, with or without a location) and runs to the next `@` line. Use this text form, not JSON: a headless run refuses a heredoc that contains JSON (`{"`). The JSON form of the usage still works where the shell is not restricted. A clean review has only the summary.

`file:line` go together; `line` is the line number in the **new** version of the file and must lie inside the diff (GitHub rejects others; the script then posts everything in the review body). A finding without a location is listed in the body. The review is a plain comment review titled `Review round <k> of <max>` (GitHub does not allow approving or requesting changes on a PR of your own account, the tags carry the meaning).

It is refused when another review was posted meanwhile (`--round` no longer matches) or the PR head moved (`--commit` no longer matches): remove the worktree (`$W remove "$dir"`) and start over from step 1, with a fresh read of the state, a new fetch, a new worktree and a new `sha`. A refused post does not use up a round.

## 5. Move the issue

- Any `[must-fix]` open, or a deferral you did not accept: `$B move <n> Todo`, then `$B order <n>` so the rework comes first.
- Round 1 with any finding at all, also only `[suggestion]`s: the same move to Todo, so the coder evaluates each suggestion once (fix, decline with a reason, or follow-up issue). `round` is 0 in the state you read for your first review.
- Otherwise (nothing open; suggestions you add in a later round do not send it back, the coder has had its pass): `$B move <n> Testing`.

`move` clears your claim. Then `$W remove "$dir"`.

## 6. Park for the user (round cap reached, or a disputed must-fix)

Do not post another review. Park the issue as the project-board skill describes (`needs-info`, a comment, `$B move <n> Triage`). The comment lists the open items, **every other open `[must-fix]` too**, and for a dispute both positions (your finding, the coder's reason, your view). The triager leaves it alone; the user decides and removes the label. The open PR stays linked. Remove the worktree if you made one (`$W remove "$dir"`).

## No board

The board commands print `SKIPPED`; do steps 2 to 4 for the issue the user names. Instead of the move, say in a comment on the issue whether the PR goes back to the coder or is ready for testing.

## Report

Issue, PR, round `k of max`, number of must-fix and suggestions per axis, your decision (Todo, Testing or parked for the user) and every disputed or deferred item with its status.
