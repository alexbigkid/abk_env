# PR mode (the reviewer agent)

Review the pull request of an issue that is in the **Review** column: the same two axes (Standards, Spec) as in [SKILL.md](SKILL.md), but the result is **one review on the PR** with tagged findings and a board move. You never change code, commit, merge or close anything.

```bash
Q=~/.claude/skills/prioritize/scripts/queue.sh
B=~/.claude/skills/project-board/scripts/board.sh
S=~/.claude/skills/review/scripts/review-state.sh
P=~/.claude/skills/review/scripts/post-review.sh
W=~/.claude/skills/review/scripts/review-worktree.sh
H=~/.claude/skills/code-issue/scripts/with-https.sh     # git over HTTPS: no SSH, no YubiKey
```

## 1. Pick the issue and read its state

The user may name an issue (always without a board). With a board take the first issue in Review that is not waiting for a human:

```bash
$Q Review | jq -r '[.issues[] | select(.labels | index("needs-info") | not)] | first | .number // empty'
$B claim Reviewer <n>
$S <n>          # pr, branch, base, headSha, mergeable, round, max, capped, handledComment, handledIsNew, unresolvedThreads
```

Note the `round` and keep it; you pass it back when you post. `"pr": null`: no open PR, `$B release <n>` and report. `capped: true`: go straight to step 6, do not review. The cap `MAX_REVIEW_ROUNDS` is defined once in `scripts/review-lib.sh`; never write the number elsewhere. The claim is the lock between two reviewers; the pins in step 4 catch the rest.

## 2. Read the PR without touching the user's checkout

```bash
$H git fetch origin <branch> <base>
dir=$($W add <branch>)                    # detached throwaway worktree: read files and run tests/linters there
sha=$(git -C "$dir" rev-parse HEAD)       # the commit you review; you pin it in step 4
git diff origin/<base>...origin/<branch>  # the change; commits: git log origin/<base>..origin/<branch> --oneline
```

Always remove the worktree when you are done, also when you stop early or fail: `$W remove "$dir"`.

## 3. Review

Standards and Spec as in SKILL.md (sources of standards, the issue as spec: `gh issue view <n>`). Without the Agent tool do the two axes yourself, one after the other, and keep them separate; with it you may run them as parallel sub-agents. Run the repo's tests and linters in the worktree. `mergeable: CONFLICTING` is a `[must-fix]` (the PR conflicts with its base).

**Round 2 or later** (`round > 0`): verify what the coder did.
- `handledIsNew: true`: read `handledComment` (the coder's `Review items handled:` summary, `pr-feedback.sh` hides it) and the unresolved threads, and check each item.
- `handledIsNew: false` (no comment since your last review, the coder gave no answer): ignore the old comment; every earlier `[must-fix]` is open unless the code shows it fixed.
- A `[must-fix]` must be really fixed in the code.
- A deferred `[suggestion]` is accepted only if its follow-up issue exists and has acceptance criteria (`gh issue view <m>`); otherwise re-mark it `[must-fix]`.
- `disputed (<reason>)` on a must-fix: do not argue it again, go to step 6.

**Classify every finding**, no untagged ones:
- `[must-fix]`: the acceptance criteria are not met, a bug, a security problem, a broken or missing test for the change, or a hard standard violation.
- `[suggestion]`: style, an alternative design, optional hardening, extra tests beyond the scope.

## 4. Post one review

```bash
$P <n> --round <round> --commit "$sha" <<'JSON'
{"summary": "## Standards\n...\n## Spec\n...",
 "findings": [{"tag": "must-fix", "body": "...", "path": "scripts/a.sh", "line": 12},
              {"tag": "suggestion", "body": "..."}]}
JSON
```

`path` and `line` go together; `line` is the line number in the **new** version of the file and must lie inside the diff (GitHub rejects others; the script then posts everything in the review body). A finding without a location is listed in the body. The review is a plain comment review titled `Review round <k> of <max>` (GitHub does not allow approving or requesting changes on a PR of your own account, the tags carry the meaning). A clean review has `"findings": []`.

It is refused when another review was posted meanwhile (`--round` no longer matches) or the PR head moved (`--commit` no longer matches): then start over from step 1.

## 5. Move the issue

- Any `[must-fix]` open, or a deferral you did not accept: `$B move <n> Todo`, then `$B order <n>` so the rework comes first.
- Nothing open (only suggestions, or accepted deferrals): `$B move <n> Testing`.

`move` clears your claim. Then `$W remove "$dir"`.

## 6. Park for the user (round cap reached, or a disputed must-fix)

Do not post another review. Park the issue as the project-board skill describes (`needs-info`, a comment, `$B move <n> Triage`). The comment lists the open items, **every other open `[must-fix]` too**, and for a dispute both positions (your finding, the coder's reason, your view). The triager leaves it alone; the user decides and removes the label. The open PR stays linked. Remove the worktree (`$W remove "$dir"`).

## No board

The board commands print `SKIPPED`; do steps 2 to 4 for the issue the user names. Instead of the move, say in a comment on the issue whether the PR goes back to the coder or is ready for testing.

## Report

Issue, PR, round `k of max`, number of must-fix and suggestions, your decision (Todo, Testing or parked for the user) and every disputed or deferred item with its status.
