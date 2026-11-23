# shellcheck shell=bash
# shellcheck disable=SC2034  # the constants are used by the scripts that source this file

#------------------------------------------------------------------------------
# review-lib.sh - shared definitions of the PR review scripts.
# Sourced after project-board/scripts/lib.sh, not executed.
#------------------------------------------------------------------------------

# The cap of review rounds per pull request. This is the ONE definition: the scripts here and
# the orchestrator read it from here, nobody repeats the number.
MAX_REVIEW_ROUNDS=10

# The visible title of a review of the reviewer: "Review round <k> of <max>".
ROUND_MARKER="Review round"

# The hidden tag at the end of every review of the reviewer. Rounds are counted by this tag, so a
# human review or comment that happens to start with the title does not count.
ROUND_TAG='<!-- abk:review-round -->'

# The summary comment of the coder: it starts with HANDLED_MARKER and ends with the hidden HANDLED_TAG, by which
# it is found (a human comment that starts like it is ignored). Same values in code-issue/scripts/pr-feedback.sh.
HANDLED_MARKER="Review items handled:"
HANDLED_TAG='<!-- abk:review-items-handled -->'

# Print the review state of the open pull request that closes an issue as JSON, or {"pr": null}. Only reviews and
# comments of trusted authors (the owner, ABK_TRUSTED_LOGINS) count; text of anyone else is never read as a state.
# Two GraphQL requests; the 50 most recently updated open PRs, the newest 50 reviews and 50 comments,
# and 50 threads are read.
load_pr_state() {
    local issue=$1 prs pr details
    # shellcheck disable=SC2016  # $vars in the queries are GraphQL variables, not shell
    prs=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -f query='
        query($owner:String!,$name:String!){repository(owner:$owner,name:$name){
          pullRequests(states:OPEN,first:50,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{number url headRefName baseRefName closingIssuesReferences(first:5){nodes{number}}}}}}')
    pr=$(jq -c --argjson n "$issue" 'first(.data.repository.pullRequests.nodes[] | select(any(.closingIssuesReferences.nodes[]; .number == $n))) // empty' <<<"$prs")
    if [ -z "$pr" ]; then
        printf '%s\n' '{"pr": null}'
        return 0
    fi
    # shellcheck disable=SC2016
    details=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -F number="$(jq -r .number <<<"$pr")" -f query='
        query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
          id headRefOid mergeable
          reviews(last:50){nodes{body createdAt author{login} commit{oid}}}
          comments(last:50){nodes{body createdAt lastEditedAt author{login}}}
          reviewThreads(first:50){nodes{isResolved}}}}}')
    jq -c --argjson pr "$pr" --argjson max "$MAX_REVIEW_ROUNDS" --arg round_tag "$ROUND_TAG" --arg handled_tag "$HANDLED_TAG" --argjson trusted "$(trusted_logins)" '
        def trusted: (.author.login // "") | ascii_downcase | IN($trusted[]);
        .data.repository.pullRequest as $p
        | [$p.reviews.nodes[] | select(trusted and (.body | contains($round_tag)))] as $round_reviews
        | ($round_reviews | length) as $rounds
        | ($round_reviews | map(.createdAt) | max) as $last_review
        | ($round_reviews | any(.commit.oid == $p.headRefOid)) as $head_reviewed
        | ([$p.comments.nodes[] | select(trusted and (.body | contains($handled_tag)))] | last) as $handled
        | (if $handled == null then null else ($handled.lastEditedAt // $handled.createdAt) end) as $handled_at
        | ($handled != null and ($last_review == null or $handled_at > $last_review)) as $handled_is_new
        | {pr: $pr.number, id: $p.id, url: $pr.url, branch: $pr.headRefName, base: $pr.baseRefName, headSha: $p.headRefOid,
           mergeable: $p.mergeable, round: $rounds, max: $max, capped: ($rounds >= $max), lastReviewAt: $last_review, headReviewed: ($head_reviewed and ($handled_is_new | not)),
           handledAt: $handled_at, handledComment: ($handled.body // null),
           handledIsNew: $handled_is_new,
           unresolvedThreads: ([$p.reviewThreads.nodes[] | select(.isResolved | not)] | length)}' <<<"$details"
}
