#!/usr/bin/env bash

#------------------------------------------------------------------------------
# pr-feedback.sh - show the open pull request of an issue and its open review feedback.
# Needs: gh (scope: repo), jq. Repo from the current directory or GH_REPO.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$(dirname "$0")/../../project-board/scripts/lib.sh"

usage() {
    cat <<USAGE
usage: pr-feedback.sh <issue-number>
Prints, as JSON, the open pull request that closes the issue and its open feedback:
{"pr": <number or null>, "branch", "url",
 "threads": [{"path", "line", "comments": [{"author", "body"}]}],     unresolved review threads only
 "comments": [{"author", "body"}], "reviews": [{"state", "author", "body"}]}
No open pull request: {"pr": null}. Cost: 2 GraphQL requests. At most 50 open PRs,
50 threads, 20 comments per thread, 30 PR comments and 20 reviews are read.
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
      comments(first:30){nodes{author{login} body}}
      reviews(first:20){nodes{state body author{login}}}}}}')
jq -c --argjson pr "$pr" '
    .data.repository.pullRequest as $p
    | {pr: $pr.number, branch: $pr.headRefName, url: $pr.url,
       threads: [$p.reviewThreads.nodes[] | select(.isResolved | not) | {path, line, comments: [.comments.nodes[] | {author: .author.login, body}]}],
       comments: [$p.comments.nodes[] | {author: .author.login, body}],
       reviews: [$p.reviews.nodes[] | select(.body != "" or .state != "COMMENTED") | {state, author: .author.login, body}]}' <<<"$details"
