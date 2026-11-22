#!/usr/bin/env bash

#------------------------------------------------------------------------------
# queue.sh - list the issues waiting for prioritization, with their blockers.
#
# With a project board: the open issues in the Triage column.
# Without a board:      all open issues of the repo.
# Output (JSON): {"board": <project number or null>, "issues": [
#   {"number", "title", "labels", "hasAcceptance",
#    "blockedBy": [{"number", "state", "status"}], "blocking": [numbers]}]}
# "status" is the board column of the blocker (null without a board or when
# the blocker is not on the board).
#
# Needs: gh (scopes: repo, project), jq. Repo from the current directory or GH_REPO.
# Cost: 2 GraphQL calls plus 1 REST call, plus one more GraphQL call per 100 items.
#------------------------------------------------------------------------------
set -euo pipefail

TRIAGE_COLUMN="triage"

die() { echo "ERROR: $*" >&2; exit 1; }

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi
[ $# -eq 0 ] || { echo "usage: queue.sh (no arguments)" >&2; exit 1; }

repo_path="{owner}/{repo}"
if [ -n "${GH_REPO:-}" ]; then repo_path=$GH_REPO; fi
repo=$(gh api "repos/$repo_path" -q .full_name) || die "cannot determine the repository"
owner=${repo%%/*}
name=${repo##*/}

# Issue fields shared by both queries.
# shellcheck disable=SC2016  # $vars in the queries are GraphQL variables, not shell
ISSUE_FIELDS='number title state body labels(first:20){nodes{name}} blockedBy(first:20){nodes{number state}} blocking(first:20){nodes{number}}'

# shellcheck disable=SC2016
project=$(gh api graphql -F owner="$owner" -F name="$name" -f query='
    query($owner:String!,$name:String!){repository(owner:$owner,name:$name){projectsV2(first:5){nodes{id number}}}}' \
    -q '.data.repository.projectsV2.nodes') || die "cannot read the projects linked to $repo"
count=$(jq 'length' <<<"$project")
[ "$count" -le 1 ] || die "$repo has $count linked project boards, cannot choose one"

if [ "$count" -eq 1 ]; then
    board=$(jq -r '.[0].number' <<<"$project")
    # shellcheck disable=SC2016
    pages=$(gh api graphql --paginate -f p="$(jq -r '.[0].id' <<<"$project")" -f query='
        query($p:ID!,$endCursor:String){node(id:$p){... on ProjectV2{items(first:100,after:$endCursor){
          pageInfo{hasNextPage endCursor}
          nodes{status:fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}
                content{... on Issue{'"$ISSUE_FIELDS"'}}}}}}}') || die "cannot read the board items (API error or rate limit)"
    items=$(jq -s '[.[].data.node.items.nodes[] | select(.content.number != null)]' <<<"$pages")
else
    board=null
    # shellcheck disable=SC2016
    pages=$(gh api graphql --paginate -F owner="$owner" -F name="$name" -f query='
        query($owner:String!,$name:String!,$endCursor:String){repository(owner:$owner,name:$name){
          issues(states:OPEN,first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{'"$ISSUE_FIELDS"'}}}}') ||
        die "cannot read the open issues (API error or rate limit)"
    items=$(jq -s '[.[].data.repository.issues.nodes[] | {status: null, content: .}]' <<<"$pages")
fi

jq --argjson board "$board" --arg triage "$TRIAGE_COLUMN" '
    def column: (.status.name // "") | sub("^[^A-Za-z0-9]+"; "");
    (map({key: (.content.number | tostring), value: (column | if . == "" then null else . end)}) | from_entries) as $columns
    | {board: $board, issues: [
        .[] | select(.content.state == "OPEN" and ($board == null or (column | ascii_downcase) == $triage))
        | .content as $c
        | {number: $c.number, title: $c.title, labels: [$c.labels.nodes[].name],
           hasAcceptance: ($c.body | test("acceptance criteria"; "i")),
           blockedBy: [$c.blockedBy.nodes[] | {number, state, status: $columns[(.number | tostring)]}],
           blocking: [$c.blocking.nodes[].number]}]}' <<<"$items"
