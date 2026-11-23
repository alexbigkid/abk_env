# shellcheck shell=bash
# shellcheck disable=SC2034  # the constants are used by the scripts that source this file

#------------------------------------------------------------------------------
# review-lib.sh - shared definitions of the PR review scripts.
# Sourced after project-board/scripts/lib.sh, not executed.
#------------------------------------------------------------------------------

# The cap of review rounds per pull request. This is the ONE definition: the scripts here and
# the orchestrator read it from here, nobody repeats the number.
MAX_REVIEW_ROUNDS=10

# A review of the reviewer starts with "Review round <k> of <max>", which is how rounds are counted.
ROUND_MARKER="Review round"

# The summary comment of the coder (see code-issue/scripts/pr-feedback.sh, same text).
HANDLED_MARKER="Review items handled:"

# Print the review state of the open pull request that closes an issue as JSON, or {"pr": null}.
# Two GraphQL requests; at most 50 open PRs, the newest 50 reviews, 30 comments and 50 threads are read.
load_pr_state() {
    local issue=$1 prs pr details
    # shellcheck disable=SC2016  # $vars in the queries are GraphQL variables, not shell
    prs=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -f query='
        query($owner:String!,$name:String!){repository(owner:$owner,name:$name){
          pullRequests(states:OPEN,first:50){nodes{number url headRefName baseRefName closingIssuesReferences(first:5){nodes{number}}}}}}')
    pr=$(jq -c --argjson n "$issue" 'first(.data.repository.pullRequests.nodes[] | select(any(.closingIssuesReferences.nodes[]; .number == $n))) // empty' <<<"$prs")
    if [ -z "$pr" ]; then
        echo '{"pr": null}'
        return 0
    fi
    # shellcheck disable=SC2016
    details=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -F number="$(jq -r .number <<<"$pr")" -f query='
        query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
          id headRefOid
          reviews(last:50){nodes{body createdAt}}
          comments(last:30){nodes{body createdAt}}
          reviewThreads(first:50){nodes{isResolved}}}}}')
    jq -c --argjson pr "$pr" --argjson max "$MAX_REVIEW_ROUNDS" --arg round_marker "$ROUND_MARKER" --arg handled_marker "$HANDLED_MARKER" '
        .data.repository.pullRequest as $p
        | ([$p.reviews.nodes[] | select(.body | startswith($round_marker))] | length) as $rounds
        | ([$p.comments.nodes[] | select(.body | startswith($handled_marker))] | last) as $handled
        | {pr: $pr.number, id: $p.id, url: $pr.url, branch: $pr.headRefName, base: $pr.baseRefName, headSha: $p.headRefOid,
           round: $rounds, max: $max, capped: ($rounds >= $max),
           handledAt: ($handled.createdAt // null), handledComment: ($handled.body // null),
           unresolvedThreads: ([$p.reviewThreads.nodes[] | select(.isResolved | not)] | length)}' <<<"$details"
}
