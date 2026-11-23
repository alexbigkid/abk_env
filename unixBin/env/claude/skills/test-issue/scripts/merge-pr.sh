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
MAX_CHECKS=100
STATE_MERGEABLE="MERGEABLE"

usage() {
    cat <<USAGE
usage: merge-pr.sh <issue-number> --commit <sha> [--dry-run]     (the options in any order)
Squash-merges the open pull request that closes the issue: title "<PR title> (#<pr>)", message "Closes #<issue>".
Refuses (exit 1) when there is no open PR, its head is not <sha> (the full sha of the commit you tested), it is not
$STATE_MERGEABLE, it has more than $MAX_CHECKS checks (they cannot all be judged), GitHub refuses the merge or does not
report the PR as merged afterwards. The checks that gate the merge are the required ones, or all of them when none
is marked required: any failed -> exit $EXIT_FAILED (the names are printed), any still running -> exit $EXIT_PENDING.
After the merge the signature of the merge commit is read; not verified -> exit $EXIT_UNVERIFIED.
--dry-run does every check and stops before the merge: prints "would merge: PR #<pr> at <sha> (<k> gating checks green)".
Success prints "merged: <sha> verified=true" (exit $EXIT_UNVERIFIED prints verified=false).
USAGE
}

# Print the checks of a pull request as JSON: {"title", "truncated", "gating": [{name, failed, pending}]}.
load_checks() {
    local number=$1 data
    # shellcheck disable=SC2016  # $vars in the query are GraphQL variables, not shell
    data=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -F number="$number" -f query='
        query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
          title
          commits(last:1){nodes{commit{statusCheckRollup{contexts(first:'"$MAX_CHECKS"'){pageInfo{hasNextPage} nodes{
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
        | {title: $p.title, truncated: ($p.commits.nodes[0].commit.statusCheckRollup.contexts.pageInfo.hasNextPage // false), gating: (if ($required | length) > 0 then $required else $all end)}' <<<"$data"
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
shift
sha=""
dry_run=""
while [ $# -gt 0 ]; do
    case "$1" in
        --commit) [ $# -ge 2 ] || usage_error; sha=$2; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        *) usage_error ;;
    esac
done
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "--commit needs the full 40-character sha of the tested commit, got '$sha'"

resolve_repo
state=$(load_pr_state "$issue")
number=$(jq -r '.pr // empty' <<<"$state")
[ -n "$number" ] || die "no open pull request closes #$issue"
head=$(jq -r .headSha <<<"$state")
[ "$head" = "$sha" ] || die "the PR head is $head, not the tested commit $sha; test again"
mergeable=$(jq -r .mergeable <<<"$state")
[ "$mergeable" = "$STATE_MERGEABLE" ] || die "PR #$number is $mergeable, not $STATE_MERGEABLE"

checks=$(load_checks "$number")
[ "$(jq -r .truncated <<<"$checks")" = "false" ] || die "PR #$number has more than $MAX_CHECKS checks; they cannot all be judged"
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
