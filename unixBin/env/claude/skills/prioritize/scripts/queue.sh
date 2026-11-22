#!/usr/bin/env bash

#------------------------------------------------------------------------------
# queue.sh - list the issues to prioritize (Triage and Todo), with their blockers.
# Needs: gh (scopes: repo, project), jq. Run "queue.sh --help" for details.
#------------------------------------------------------------------------------
set -euo pipefail

STATUS_FIELD="Status"
TRIAGE_COLUMN="triage"
TODO_COLUMN="todo"

usage() {
    cat <<USAGE
usage: queue.sh
Lists the issues to prioritize, with their blockers, as JSON, in board order.
  With a project board:  the open issues in the Triage and Todo columns.
  Without a board:       all open issues of the repo.
The repo must have exactly one linked project board, or none.
Output: {"board": <project number or null>, "issues": [
  {"number", "title", "column", "labels", "hasAcceptance",
   "blockedBy": [{"number", "state", "status"}], "blocking": [numbers]}]}
"status" is the board column of a blocker (null without a board or when the
blocker is not on the board). At most 20 blockers per issue are read.
Repo from the current directory or GH_REPO. Cost: 2 GraphQL calls and 1 REST call,
plus one more GraphQL call per 100 items.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -eq 0 ] || { usage >&2; exit 1; }

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
          nodes{status:fieldValueByName(name:"'"$STATUS_FIELD"'"){... on ProjectV2ItemFieldSingleSelectValue{name}}
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

jq --argjson board "$board" --arg triage "$TRIAGE_COLUMN" --arg todo "$TODO_COLUMN" '
    def column: (.status.name // "") | sub("^[^A-Za-z0-9]+"; "");
    (map({key: (.content.number | tostring), value: (column | if . == "" then null else . end)}) | from_entries) as $columns
    | {board: $board, issues: [
        .[] | select(.content.state == "OPEN" and ($board == null or (column | ascii_downcase | IN($triage, $todo))))
        | .content as $c
        | {number: $c.number, title: $c.title, column: (column | if . == "" then null else . end), labels: [$c.labels.nodes[].name],
           hasAcceptance: ($c.body | test("acceptance criteria"; "i")),
           blockedBy: [$c.blockedBy.nodes[] | {number, state, status: $columns[(.number | tostring)]}],
           blocking: [$c.blocking.nodes[].number]}]}' <<<"$items"
