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

The user may name an issue. Otherwise take the first issue in Review that is not waiting for a human:

```bash
$Q Review | jq -r '[.issues[] | select(.labels | index("needs-info") | not)] | first | .number // empty'
$B claim Reviewer <n>
$S <n>          # pr, branch, base, round, max, capped, handledComment, unresolvedThreads
```

`"pr": null`: no open PR, release your claim and report. `capped: true`: go straight to step 6, do not review. The cap `MAX_REVIEW_ROUNDS` (10) is defined once in `scripts/review-lib.sh`; never write the number elsewhere.

## 2. Read the PR without touching the user's checkout

```bash
$H git fetch origin <branch> <base>
dir=$($W add <branch>)                    # detached throwaway worktree: read files and run tests/linters there
git diff origin/<base>...origin/<branch>  # the change; commits: git log origin/<base>..origin/<branch> --oneline
```

## 3. Review

Standards and Spec as in SKILL.md (sources of standards, the issue as spec: `gh issue view <n>`). Without the Agent tool do the two axes yourself, one after the other, and keep them separate; with it you may run them as parallel sub-agents. Run the repo's tests and linters in the worktree.

**Round 2 or later** (`round > 0`): read `handledComment` (the coder's `Review items handled:` summary, `pr-feedback.sh` hides it) and the unresolved threads, and verify each item:
- a `[must-fix]` must be really fixed in the code;
- a deferred `[suggestion]` is accepted only if its follow-up issue exists and has acceptance criteria (`gh issue view <m>`); otherwise re-mark it `[must-fix]`;
- `disputed (<reason>)` on a must-fix: do not argue it again, go to step 6.

**Classify every finding**, no untagged ones:
- `[must-fix]`: the acceptance criteria are not met, a bug, a security problem, a broken or missing test for the change, or a hard standard violation.
- `[suggestion]`: style, an alternative design, optional hardening, extra tests beyond the scope.

## 4. Post one review

```bash
$P <n> <<'JSON'
{"summary": "## Standards\n...\n## Spec\n...",
 "findings": [{"tag": "must-fix", "body": "...", "path": "scripts/a.sh", "line": 12},
              {"tag": "suggestion", "body": "..."}]}
JSON
```

It posts a plain comment review titled `Review round <k> of <max>` (GitHub does not allow approving or requesting changes on a PR of your own account, the tags carry the meaning), with inline comments where `path` and `line` are given. A clean review has `"findings": []`.

## 5. Move the issue

- Any `[must-fix]` open, or a deferral you did not accept: `$B move <n> Todo`, then `$B order <n>` so the rework comes first.
- Nothing open: `$B move <n> Testing`.

`move` clears your claim. Then remove the worktree: `$W remove "$dir"`.

## 6. Park for the user (round cap reached, or a disputed must-fix)

Do not post another review. Park the issue as the project-board skill describes (`needs-info`, a comment, `$B move <n> Triage`). The comment lists the open items, and for a dispute both positions (your finding, the coder's reason, your view). The triager leaves it alone; the user decides and removes the label. The open PR stays linked.

## No board

The board commands print `SKIPPED`; do steps 2 to 4 for the issue the user names. Instead of the move, say in a comment on the issue whether the PR goes back to the coder or is ready for testing.

## Report

Issue, PR, round `k of max`, number of must-fix and suggestions, your decision (Todo, Testing or parked for the user) and every disputed or deferred item with its status.
