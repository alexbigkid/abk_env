#!/usr/bin/env bash

#------------------------------------------------------------------------------
# pr-feedback.sh - show the open pull request of an issue and its open review feedback.
# Needs: gh (scope: repo), jq. Repo from the current directory or GH_REPO.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$(dirname "$0")/../../project-board/scripts/lib.sh"

HANDLED_MARKER="Review items handled:"

usage() {
    cat <<USAGE
usage: pr-feedback.sh <issue-number>
Prints, as JSON, the open pull request that closes the issue and its open feedback:
{"pr": <number or null>, "branch", "url", "handledAt",
 "threads": [{"path", "line", "comments": [{"author", "body"}]}],     unresolved review threads only
 "comments": [{"author", "body"}], "reviews": [{"state", "author", "body"}]}
Comments and reviews are listed only when they are newer than the last PR comment that starts
with "$HANDLED_MARKER" (the coder's summary of the items it handled); "handledAt" is its time.
No open pull request: {"pr": null}. Cost: 1 GraphQL request without a PR, otherwise 2. At most
50 open PRs, 50 threads, 20 comments per thread, the newest 30 PR comments and 20 reviews are read.
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -eq 1 ] || usage_error
require_issue_numbers "$1"
resolve_repo

# shellcheck disable=SC2016  # $vars in the queries are GraphQL variables, not shell
prs=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -f query='
    query($owner:String!,$name:String!){repository(owner:$owner,name:$name){
      pullRequests(states:OPEN,first:50){nodes{number url headRefName closingIssuesReferences(first:5){nodes{number}}}}}}')
pr=$(jq -c --argjson n "$1" 'first(.data.repository.pullRequests.nodes[] | select(any(.closingIssuesReferences.nodes[]; .number == $n))) // empty' <<<"$prs")
if [ -z "$pr" ]; then
    echo '{"pr": null}'
    exit 0
fi

# shellcheck disable=SC2016
details=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -F number="$(jq -r .number <<<"$pr")" -f query='
    query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
      reviewThreads(first:50){nodes{isResolved path line comments(first:20){nodes{author{login} body}}}}
      comments(last:30){nodes{author{login} body createdAt}}
      reviews(last:20){nodes{state body createdAt author{login}}}}}}')
jq -c --argjson pr "$pr" --arg marker "$HANDLED_MARKER" '
    .data.repository.pullRequest as $p
    | ([$p.comments.nodes[] | select(.body | startswith($marker)) | .createdAt] | max // "") as $since
    | {pr: $pr.number, branch: $pr.headRefName, url: $pr.url, handledAt: ($since | if . == "" then null else . end),
       threads: [$p.reviewThreads.nodes[] | select(.isResolved | not) | {path, line, comments: [.comments.nodes[] | {author: .author.login, body}]}],
       comments: [$p.comments.nodes[] | select(.createdAt > $since and (.body | startswith($marker) | not)) | {author: .author.login, body}],
       reviews: [$p.reviews.nodes[] | select(.createdAt > $since and (.body != "" or .state != "COMMENTED")) | {state, author: .author.login, body}]}' <<<"$details"
