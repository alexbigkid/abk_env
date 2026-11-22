#!/usr/bin/env bash

#------------------------------------------------------------------------------
# queue.sh - list the issues to prioritize (Triage and Todo), with their blockers.
# Needs: gh (scopes: repo, project), jq. Run "queue.sh --help" for details.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$(dirname "$0")/../../project-board/scripts/lib.sh"

STATUS_FIELD="Status"
TRIAGE_COLUMN="triage"
TODO_COLUMN="todo"
RANKED_MARKER="Queue position:"

# Issue fields shared by the board and the no-board query.
ISSUE_FIELDS='number title state body labels(first:20){nodes{name}} blockedBy(first:20){nodes{number state}} blocking(first:20){nodes{number}}'

usage() {
    cat <<USAGE
usage: queue.sh
Lists the issues to prioritize, with their blockers, as JSON, in board order.
  With a project board:  the open issues in the Triage and Todo columns.
  Without a board:       all open issues of the repo.
The repo must have exactly one linked project board, or none.
Output: {"board": <project number or null>, "issues": [
  {"number", "title", "column", "labels", "hasAcceptance", "ranked",
   "blockedBy": [{"number", "state", "status"}], "blocking": [numbers]}]}
"status" is the board column of a blocker (null without a board or when the
blocker is not on the board). "ranked" is true when the issue already has a
"$RANKED_MARKER" comment (read without a board only). At most 20 labels, blockers and
blocked issues per issue are read. Repo from the current directory or GH_REPO.
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -eq 0 ] || usage_error
resolve_repo

# shellcheck disable=SC2016  # $vars in the queries are GraphQL variables, not shell
first_page=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -f query='
    query($owner:String!,$name:String!){repository(owner:$owner,name:$name){projectsV2(first:5){nodes{id number
      items(first:100){pageInfo{hasNextPage endCursor}
        nodes{status:fieldValueByName(name:"'"$STATUS_FIELD"'"){... on ProjectV2ItemFieldSingleSelectValue{name}}
              content{... on Issue{'"$ISSUE_FIELDS"'}}}}}}}}')
projects=$(jq -c '.data.repository.projectsV2.nodes' <<<"$first_page")
count=$(jq 'length' <<<"$projects")
[ "$count" -le 1 ] || die "$REPO has $count linked project boards, cannot choose one"

if [ "$count" -eq 1 ]; then
    board=$(jq -r '.[0].number' <<<"$projects")
    project_id=$(jq -r '.[0].id' <<<"$projects")
    items=$(jq -c '[.[0].items.nodes[] | select(.content.number != null)]' <<<"$projects")
    more=$(jq -r '.[0].items.pageInfo.hasNextPage' <<<"$projects")
    cursor=$(jq -r '.[0].items.pageInfo.endCursor' <<<"$projects")
    while [ "$more" = "true" ]; do
        # shellcheck disable=SC2016
        page=$(gql -f p="$project_id" -f c="$cursor" -f query='
            query($p:ID!,$c:String){node(id:$p){... on ProjectV2{items(first:100,after:$c){pageInfo{hasNextPage endCursor}
              nodes{status:fieldValueByName(name:"'"$STATUS_FIELD"'"){... on ProjectV2ItemFieldSingleSelectValue{name}}
                    content{... on Issue{'"$ISSUE_FIELDS"'}}}}}}}')
        items=$(jq -c --argjson more "$(jq -c '[.data.node.items.nodes[] | select(.content.number != null)]' <<<"$page")" '. + $more' <<<"$items")
        more=$(jq -r '.data.node.items.pageInfo.hasNextPage' <<<"$page")
        cursor=$(jq -r '.data.node.items.pageInfo.endCursor' <<<"$page")
    done
else
    board=null
    items="[]"
    more=true
    cursor=""
    while [ "$more" = "true" ]; do
        # shellcheck disable=SC2016
        page=$(gql -f owner="$OWNER" -f name="$REPO_NAME" ${cursor:+-f c="$cursor"} -f query='
            query($owner:String!,$name:String!,$c:String){repository(owner:$owner,name:$name){
              issues(states:OPEN,first:100,after:$c){pageInfo{hasNextPage endCursor}
                nodes{'"$ISSUE_FIELDS"' comments(last:20){nodes{body}}}}}}')
        items=$(jq -c --argjson more "$(jq -c '[.data.repository.issues.nodes[] | {status: null, content: .}]' <<<"$page")" '. + $more' <<<"$items")
        more=$(jq -r '.data.repository.issues.pageInfo.hasNextPage' <<<"$page")
        cursor=$(jq -r '.data.repository.issues.pageInfo.endCursor' <<<"$page")
    done
fi

jq --argjson board "$board" --arg triage "$TRIAGE_COLUMN" --arg todo "$TODO_COLUMN" --arg marker "$RANKED_MARKER" '
    def column: (.status.name // "") | sub("^[^A-Za-z0-9]+"; "");
    (map({key: (.content.number | tostring), value: (column | if . == "" then null else . end)}) | from_entries) as $columns
    | {board: $board, issues: [
        .[] | select(.content.state == "OPEN" and ($board == null or (column | ascii_downcase | IN($triage, $todo))))
        | .content as $c
        | {number: $c.number, title: $c.title, column: (column | if . == "" then null else . end), labels: [$c.labels.nodes[].name],
           hasAcceptance: ($c.body | test("acceptance criteria"; "i")),
           ranked: (($c.comments.nodes // []) | any(.body | contains($marker))),
           blockedBy: [$c.blockedBy.nodes[] | {number, state, status: $columns[(.number | tostring)]}],
           blocking: [$c.blocking.nodes[].number]}]}' <<<"$items"
