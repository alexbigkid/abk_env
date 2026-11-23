#!/usr/bin/env bash

#------------------------------------------------------------------------------
# merge-pr.sh - squash-merge the open pull request of an issue, only when it is safe.
# GitHub creates and signs the merge commit, so no key and no push are needed.
# Needs: gh (scope: repo), jq. Repo from the current directory or GH_REPO.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill, review-lib.sh to the review skill
source "$(dirname "$0")/../../project-board/scripts/lib.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/../../review/scripts/review-lib.sh"

EXIT_FAILED=2
EXIT_PENDING=3
EXIT_UNVERIFIED=4

usage() {
    cat <<USAGE
usage: merge-pr.sh <issue-number> --commit <sha> [--dry-run]
Squash-merges the open pull request that closes the issue (message "Closes #<issue>").
Refuses (exit 1) when there is no open PR, its head is not <sha> (the commit you tested), it conflicts,
or GitHub does not say MERGEABLE. The checks that gate the merge are the required ones, or all of them
when none is marked required: any failed -> exit $EXIT_FAILED (the names are printed), any still running -> exit $EXIT_PENDING.
After the merge it reads the signature of the merge commit; not verified -> exit $EXIT_UNVERIFIED.
--dry-run does every check and stops before the merge. Prints "merged: <sha> verified=true" on success.
USAGE
}

# Print the checks of a pull request as JSON: {"title", "gating": [{name, failed, pending}]}.
load_checks() {
    local number=$1 data
    # shellcheck disable=SC2016  # $vars in the query are GraphQL variables, not shell
    data=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -F number="$number" -f query='
        query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
          title
          commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100){nodes{
            __typename
            ... on CheckRun{name status conclusion isRequired(pullRequestNumber:$number)}
            ... on StatusContext{context state isRequired(pullRequestNumber:$number)}}}}}}}}}}')
    jq -c '
        .data.repository.pullRequest as $p
        | [$p.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?
           | {name: (.name // .context), required: .isRequired,
              failed: (if .__typename == "CheckRun"
                         then (.status == "COMPLETED" and (.conclusion | IN("FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE")))
                         else (.state | IN("FAILURE", "ERROR")) end),
              pending: (if .__typename == "CheckRun" then .status != "COMPLETED" else (.state | IN("PENDING", "EXPECTED")) end)}] as $all
        | ($all | map(select(.required))) as $required
        | {title: $p.title, gating: (if ($required | length) > 0 then $required else $all end)}' <<<"$data"
}

# Print the merge commit of a pull request and whether GitHub signed it: "<sha> <true|false>".
read_merge_commit() {
    local number=$1 data
    # shellcheck disable=SC2016
    data=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -F number="$number" -f query='
        query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
          state mergeCommit{oid signature{isValid}}}}}')
    jq -r '.data.repository.pullRequest | select(.state == "MERGED") | "\(.mergeCommit.oid) \(.mergeCommit.signature.isValid // false)"' <<<"$data"
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -ge 3 ] || usage_error
issue=$1
require_issue_numbers "$issue"
[ "$2" = "--commit" ] || usage_error
sha=$3
dry_run=""
if [ $# -eq 4 ] && [ "$4" = "--dry-run" ]; then dry_run=1; elif [ $# -ne 3 ]; then usage_error; fi
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "'$sha' is not a full commit sha"

resolve_repo
state=$(load_pr_state "$issue")
number=$(jq -r '.pr // empty' <<<"$state")
[ -n "$number" ] || die "no open pull request closes #$issue"
head=$(jq -r .headSha <<<"$state")
[ "$head" = "$sha" ] || die "the PR head is $head, not the tested commit $sha; test again"
mergeable=$(jq -r .mergeable <<<"$state")
[ "$mergeable" = "MERGEABLE" ] || die "PR #$number is $mergeable, not MERGEABLE"

checks=$(load_checks "$number")
failed=$(jq -r '[.gating[] | select(.failed) | .name] | join(", ")' <<<"$checks")
if [ -n "$failed" ]; then echo "checks failed: $failed" >&2; exit "$EXIT_FAILED"; fi
pending=$(jq -r '[.gating[] | select(.pending) | .name] | join(", ")' <<<"$checks")
if [ -n "$pending" ]; then echo "checks still running: $pending" >&2; exit "$EXIT_PENDING"; fi

if [ -n "$dry_run" ]; then
    echo "would merge: PR #$number at $sha ($(jq '.gating | length' <<<"$checks") gating checks green)"
    exit 0
fi

gh pr merge "$number" --squash --match-head-commit "$sha" --subject "$(jq -r .title <<<"$checks") (#$number)" --body "Closes #$issue" >/dev/null ||
    die "the merge of PR #$number was refused"
read -r merge_sha verified <<<"$(read_merge_commit "$number")"
[ -n "${merge_sha:-}" ] || die "PR #$number is not merged according to GitHub; read it again"
echo "merged: $merge_sha verified=$verified"
[ "$verified" = "true" ] || exit "$EXIT_UNVERIFIED"
