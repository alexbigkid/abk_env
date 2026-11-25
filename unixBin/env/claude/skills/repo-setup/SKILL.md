---
name: repo-setup
description: Set up a GitHub repository for the agent issue workflow (triager, coder, reviewer, tester, orchestrator) with the same GitHub-side settings as abk_env - ruleset on main, project board and its workflows, labels, Actions permissions, optional release flow - then verify each one. Use when the user wants another repo prepared like abk_env, asks to protect main, or to "set up the repo the same way".
---

# Repo setup

Brings a GitHub repository to the same **GitHub-side** state as `alexbigkid/abk_env`, the reference repo. The local side (skills, agents, CLAUDE.md, the coder's GPG key) needs nothing per repo: it comes from `~/.claude`, symlinked to abk_env by `unixBin/setClaudeEnv.sh`, and the coder key is registered on the GitHub account once (`code-issue/GIT-SETUP.md`).

Run it from inside a clone of the target repo. Every step is **check, then change, then verify**. A step that already matches is left alone. Show the user the planned changes (steps 1 to 6) and get a go-ahead before the first change: these are settings of a shared repo. Never weaken a setting the repo already has without asking (for example a ruleset with stricter rules, or required approvals).

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)   # owner/name
OWNER=${REPO%/*}
REF=alexbigkid/abk_env                                          # the reference repo
```

`OWNER` is a user in the commands below (`user(login:)`, `/users/`). For an organisation use `organization(login:)` and `/orgs/`.

## 0. Preflight

- `gh auth status` lists the scopes `repo`, `workflow`, `project` and `read:user`. A missing one: the user runs `gh auth refresh -h github.com -s <scope>`.
- The user is an admin of the repo: `gh api repos/$REPO --jq .permissions.admin` prints `true`.
- Find whatever pushes to `main` directly, because the ruleset (step 1) refuses it from then on:
  ```bash
  grep -rnE "git push[^|;]*(main|HEAD:main|HEAD:refs/heads/main)" . --exclude-dir=.git --exclude-dir=node_modules 2>/dev/null
  ```
  This searches the whole tree, so any layout is covered. Report every hit to the user. A workflow or script that pushes to `main` must be changed to open a PR first (abk_env's release flow in step 6 shows how), or the user accepts that it breaks.

## 1. Ruleset `protect-main`

The rules and why:

| Rule | Effect | Why |
|---|---|---|
| `pull_request`, 0 approvals | No direct push to `main`, only PR merges | The agents act with the owner's login, and GitHub never lets a PR's author approve it: 1+ approvals would block every merge |
| `non_fast_forward` | No force-push to `main` | History cannot be rewritten |
| `deletion` | `main` cannot be deleted | |
| `required_signatures` | Every commit on `main` has a verified signature | Merges made by GitHub are GitHub-signed, so the tester's squash merge and the release merge pass |
| no status checks | — | Our pipelines do not run on PRs; a required check would never report and block every merge |
| no bypass actors | Applies to admins too | A bypass for the owner is a bypass for the agents |

Check first: `gh api repos/$REPO/rulesets --jq '.[] | "\(.id) \(.name) \(.enforcement)"'`. If `protect-main` exists, compare it (`gh api repos/$REPO/rulesets/<id>`) and update it with `PUT` instead of creating a second one. Rulesets of another name: show them to the user and leave them alone.

```bash
gh api -X POST "repos/$REPO/rulesets" --input - <<'EOF'      # or: -X PUT repos/$REPO/rulesets/<id>
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_signatures" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash", "merge", "rebase"] } }
  ]
}
EOF
```

A private repo on a free plan cannot have rulesets (the API answers 403 with an upgrade hint): stop this step and tell the user.

Verify: `gh api repos/$REPO/rules/branches/main --jq '[.[].type]'` lists `deletion`, `non_fast_forward`, `required_signatures`, `pull_request`. Do not test by pushing to `main`: if the rule were missing, the test would change `main`. The first merge by the tester is the positive check (a GitHub-signed squash merge passes).

## 2. Repository merge settings

abk_env keeps GitHub's defaults: squash, merge and rebase allowed, `delete_branch_on_merge` off (the orchestrator's `cleanup-merged.sh` deletes the merged branch, local and remote). Check:

```bash
gh api repos/$REPO --jq '{allow_squash_merge, delete_branch_on_merge, has_issues, has_projects}'
```

`allow_squash_merge` and `has_issues` must be `true` (the tester squash-merges; the workflow lives in issues). Change nothing else.

## 3. Actions workflow permissions

Default token permissions stay `read`; workflows ask for more per job. "Allow GitHub Actions to create and approve pull requests" is needed **only** for the release flow (step 6): it lets the Release job open and merge the release PR.

```bash
gh api repos/$REPO/actions/permissions/workflow                                      # check
gh api -X PUT repos/$REPO/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true       # only with the release flow
```

## 4. Labels

The agents use these labels (they create a missing one with `--force`, but creating them up front keeps the colours and descriptions the same). `--force` updates an existing label, so this is safe to rerun:

```bash
gh label create bug         --force --color d73a4a --description "Something isn't working"
gh label create feature     --force --color b40bb0 --description "New feature"
gh label create enhancement --force --color a2eeef --description "New feature or request"
gh label create docs        --force --color 0075ca --description "Improvements or additions to documentation"
gh label create research    --force --color 1d76db --description "Research task"
gh label create test        --force --color 0e8a16 --description "Tests"
gh label create needs-info  --force --color D93F0B --description "Waiting for a decision or information"
```

The coder takes the branch type from the label: `bug` B, `feature`/`enhancement` F, `docs` D, `research` R, `test` T.

## 5. Project board

1. **Board.** Check `gh project list --owner $OWNER` for a project titled like the repo and linked to it (`gh api graphql -f query='{repository(owner:"'$OWNER'",name:"'${REPO#*/}'"){projectsV2(first:5){nodes{number title}}}}'`). None: run the `/gh-create-project-board` command (copies `board-template`: Status Triage, Todo, Doing, Review, Testing, Done; Priority P0-P2; Size XS-XL; Estimate; Iteration; Start date; End date; and links it to the repo).
2. **Agent issue field.** Account-wide, made once: a single-select issue field `Agent` with Triager, Coder, Reviewer, Tester (Settings > Issue fields). Check with `board.sh info <n>` on any issue of the repo: it prints an `Agent:` line, or the error `issue field 'Agent' not found`.
3. **Board workflows.** The API can read them but not change them, and `gh project copy` does not copy them, so the **user** sets them in the board's Settings > Workflows. Read the reference and the new board side by side:
   ```bash
   wf() { gh api graphql -f query="{user(login:\"$OWNER\"){projectV2(number:$1){workflows(first:20){nodes{name enabled}}}}}" --jq '.data.user.projectV2.workflows.nodes[] | "\(.enabled)\t\(.name)"'; }
   wf 12        # abk_env's board
   wf <new>
   ```
   Target state (same as abk_env's board):

   | Workflow | State | Note |
   |---|---|---|
   | Auto-add sub-issues to project | on | |
   | Auto-archive items | on | filter `is:issue is:closed updated:<@today-104w` (`2y` is not understood and archives every closed item) |
   | Auto-close issue | on | |
   | Code changes requested | on | |
   | Code review approved | on | |
   | Item added to project | on | status Triage |
   | Item closed | on | status Done |
   | Item reopened | on | |
   | **Pull request linked to issue** | **off** | otherwise opening the PR flips the issue back to Todo |
   | **Pull request merged** | **off** | the tester moves the issue to Done itself |

   Walk the user through the differences one at a time, then read `wf <new>` again to verify.
4. **Smoke test.** Create a throwaway issue only if the user agrees, then `board.sh add <n>` (lands in Triage), `board.sh info <n>`, `board.sh claim Triager <n>`, `board.sh release <n>`, close it. It must end in Done.

## 6. Optional: release flow

Only if the user wants `git rel-patch|rel-minor|rel-major` releases in this repo. abk_env's flow: the alias pushes only a `rel-<type>` tag; the pipeline tests that commit; its Release job bumps `VERSION` on a `release/vX.Y.Z` branch, opens and squash-merges the PR "Release vX.Y.Z" with the run's own token, tags `vX.Y.Z` and deletes the tag and branch (details in abk_env's `CLAUDE.md`, "Version Management Workflow"). Needs:

- step 3's "create and approve pull requests" on;
- from abk_env: `.github/scripts/release.sh` (adjust its path to `nextVersion.sh`), `unixBin/nextVersion.sh`, a `VERSION` file, and the Release job, the `rel-*` tag trigger, the concurrency group and each job's failure step from `.github/workflows/pipeline.yml`;
- the aliases are global already (`unixBin/setGitAliases.sh`) and work in any repo.

This is code in the target repo, so it goes through an issue and the coder, not through this skill.

## 7. Report

One table: each step, what was found, what was changed, how it was verified, and what the user still has to do by hand (board workflows, a skipped step). Settings changed by the session are listed with the exact API call.
