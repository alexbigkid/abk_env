#!/usr/bin/env bash

#------------------------------------------------------------------------------
# cleanup-merged.sh - after the pull request of an issue is merged: bring the checkout back to an up-to-date
# default branch and delete ONLY the merged branch (local and remote). No agent, no board access.
# Needs: gh, git. Run inside the repo checkout (or set GH_REPO for gh).
#------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/lib.sh"
# shellcheck disable=SC1091  # git over HTTPS like the agents' git commands (with-https.sh does the same)
source "${HTTPS_ENV_SCRIPT:-$SCRIPT_DIR/../../code-issue/scripts/https-env.sh}"

usage() {
    cat <<USAGE
usage: cleanup-merged.sh <issue>
After the pull request that closes <issue> is merged: switch the checkout to the default branch and pull it
(only with a clean tree on the merged branch), then delete the merged branch locally and on GitHub, each only
when its tip is exactly the merged head commit of the pull request. Nothing else is touched.
Exit code 0 also when it deliberately kept or skipped something; non-zero only for a real error.
USAGE
}

# Print a line of the report.
say() { echo "cleanup #$ISSUE: $*"; }

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    ""|*[!0-9]*) usage_error ;;
esac
[ $# -eq 1 ] || usage_error
ISSUE=$1

default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name) || die "cannot read the default branch"
[ -n "$default_branch" ] || die "cannot read the default branch"

# The merged pull request that closes the issue: the highest number in state MERGED.
pr_numbers=$(gh issue view "$ISSUE" --json closedByPullRequestsReferences -q '.closedByPullRequestsReferences[].number' | sort -rn) || die "cannot read the pull requests of #$ISSUE"
pr_json=""
while read -r number; do
    [ -n "$number" ] || continue
    candidate=$(gh pr view "$number" --json number,state,headRefName,headRefOid,baseRefName,isCrossRepository,mergeCommit) || die "cannot read pull request #$number"
    if [ "$(jq -r .state <<<"$candidate")" = "MERGED" ]; then pr_json=$candidate; break; fi
done <<<"$pr_numbers"
if [ -z "$pr_json" ]; then say "no merged pull request closes it, nothing touched"; exit 0; fi

pr=$(jq -r .number <<<"$pr_json")
branch=$(jq -r .headRefName <<<"$pr_json")
head_oid=$(jq -r '.headRefOid // ""' <<<"$pr_json")
merge_oid=$(jq -r '.mergeCommit.oid // ""' <<<"$pr_json")
base=$(jq -r .baseRefName <<<"$pr_json")

# Verify the merge before anything is touched.
if [ "$(jq -r .isCrossRepository <<<"$pr_json")" != "false" ]; then say "pull request #$pr comes from a fork, refused, nothing touched"; exit 0; fi
if [ -z "$branch" ] || ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then say "pull request #$pr has no usable branch name, refused, nothing touched"; exit 0; fi
if [ "$branch" = "$default_branch" ]; then say "the branch of pull request #$pr is the default branch '$default_branch', refused, nothing touched"; exit 0; fi
if [ "$base" != "$default_branch" ]; then say "pull request #$pr was merged into '$base', not the default branch '$default_branch', nothing touched"; exit 0; fi
if ! [[ "$head_oid" =~ ^[0-9a-f]{40}$ ]] || ! [[ "$merge_oid" =~ ^[0-9a-f]{40}$ ]]; then say "pull request #$pr has no usable head or merge commit, nothing touched"; exit 0; fi

git fetch origin "$default_branch" >/dev/null 2>&1 || die "cannot fetch '$default_branch' from origin"
if ! git merge-base --is-ancestor "$merge_oid" "refs/remotes/origin/$default_branch" 2>/dev/null; then
    say "merge commit ${merge_oid:0:7} of pull request #$pr is not on $default_branch yet, nothing touched"
    exit 0
fi
say "pull request #$pr (branch $branch) is merged as ${merge_oid:0:7}"

# Bring the checkout up to date: only a clean tree on the merged branch is switched.
current=$(git branch --show-current)
if [ "$current" = "$branch" ] && [ -z "$(git status --porcelain)" ]; then
    git switch "$default_branch" >/dev/null 2>&1 || die "cannot switch to $default_branch"
    git pull --ff-only origin "$default_branch" >/dev/null 2>&1 || die "cannot fast-forward $default_branch"
    say "switched to $default_branch and pulled it"
    current=$default_branch
elif [ "$current" = "$branch" ]; then
    say "kept the checkout on $branch: the working tree is not clean (not switched, not pulled)"
else
    say "kept the checkout on '${current:-a detached head}': it is not the merged branch (not switched, not pulled)"
fi

# Local branch: only when it is the merged head commit and not checked out.
if local_tip=$(git rev-parse --verify --quiet "refs/heads/$branch"); then
    if [ "$current" = "$branch" ]; then
        say "kept local branch $branch: it is checked out"
    elif [ "$local_tip" = "$head_oid" ]; then
        git branch -D "$branch" >/dev/null
        say "deleted local branch $branch"
    else
        say "kept local branch $branch: its tip ${local_tip:0:7} is not the merged head ${head_oid:0:7}"
    fi
else
    say "no local branch $branch"
fi

# Remote branch: only when it still points to the merged head commit (deleted with a lease on it).
remote_tip=$(git ls-remote --heads origin "refs/heads/$branch" | cut -f1) || die "cannot read the remote branch $branch"
if [ -z "$remote_tip" ]; then
    say "remote branch $branch is already deleted"
    git update-ref -d "refs/remotes/origin/$branch" 2>/dev/null || true
elif [ "$remote_tip" = "$head_oid" ]; then
    git push origin "--force-with-lease=refs/heads/$branch:$head_oid" --delete "refs/heads/$branch" >/dev/null 2>&1 || die "cannot delete remote branch $branch"
    git update-ref -d "refs/remotes/origin/$branch" 2>/dev/null || true
    say "deleted remote branch $branch"
else
    say "kept remote branch $branch: its tip ${remote_tip:0:7} is not the merged head ${head_oid:0:7}"
fi
