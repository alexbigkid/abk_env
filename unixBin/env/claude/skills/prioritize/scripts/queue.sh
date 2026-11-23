#!/usr/bin/env bash

#------------------------------------------------------------------------------
# queue.sh - list the issues of board columns (default Triage and Todo), with their blockers.
# Needs: gh (scopes: repo, project), jq. Run "queue.sh --help" for details.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$(dirname "$0")/../../project-board/scripts/lib.sh"

STATUS_FIELD="Status"
DEFAULT_COLUMNS=(triage todo)
RANKED_MARKER="Queue position:"

# Issue fields shared by the board and the no-board query.
AGENT_FIELD="Agent"
ISSUE_FIELDS='number title state closedAt body repository{nameWithOwner} labels(first:20){nodes{name}}
    issueFieldValues(first:10){nodes{... on IssueFieldSingleSelectValue{name field{... on IssueFieldSingleSelect{name}}}}}
    closedByPullRequestsReferences(first:5){nodes{number state}}
    blockedBy(first:20){nodes{number state repository{nameWithOwner}}} blocking(first:20){nodes{number repository{nameWithOwner}}}'

usage() {
    cat <<USAGE
usage: queue.sh [column...]
Lists the issues of board columns, with their blockers, as JSON, in board order
(the array order is the order on the board, top first; there is no position field).
  With a project board:  the open issues in the given columns (names without emoji, any case),
                         default Triage and Todo, for example: queue.sh Review (a name no issue is in gives an
                         empty list, it is not checked against the board). Issues in other
                         columns are not listed; they only appear as blockers.
                         The column Done lists its closed issues; archive columns Done-<year>[-<month>]
                         are never listed.
  Without a board:       all open issues of the repo.
The repo must have exactly one linked project board, or none.
Output: {"board": <project number or null>, "issues": [
  {"number", "title", "closedAt", "column", "labels", "agent", "openPrs", "hasAcceptance", "ranked",
   "blockedBy": [{"number", "state", "status", "repo"}], "blocking": [numbers]}]}
"agent" is the Agent issue field (the claim of a running agent) or null; "openPrs" are the numbers of the open
pull requests that close the issue. "status" is the board column of a blocker (null without a board or when the
blocker is not on the board). "ranked" is true when the issue already has a
"$RANKED_MARKER" comment; it is read without a board only and is false with a board.
"repo" (owner/name) is only present for a blocker of another repository, which is
listed as "owner/name#number" in "blocking". Issues of other repositories on the board
are ignored. At most 20 labels, blockers and blocked issues per issue are read.
Repo from the current directory or GH_REPO.
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
if [ $# -eq 0 ]; then set -- "${DEFAULT_COLUMNS[@]}"; fi
wanted_columns=$(printf '%s\n' "$@" | tr '[:upper:]' '[:lower:]' | jq -R . | jq -sc .)
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
    cursor_args=()
    while [ "$more" = "true" ]; do
        # shellcheck disable=SC2016
        page=$(gql -f owner="$OWNER" -f name="$REPO_NAME" ${cursor_args[@]+"${cursor_args[@]}"} -f query='
            query($owner:String!,$name:String!,$c:String){repository(owner:$owner,name:$name){
              issues(states:OPEN,first:100,after:$c){pageInfo{hasNextPage endCursor}
                nodes{'"$ISSUE_FIELDS"' comments(last:20){nodes{body}}}}}}')
        items=$(jq -c --argjson more "$(jq -c '[.data.repository.issues.nodes[] | {status: null, content: .}]' <<<"$page")" '. + $more' <<<"$items")
        more=$(jq -r '.data.repository.issues.pageInfo.hasNextPage' <<<"$page")
        cursor_args=(-f c="$(jq -r '.data.repository.issues.pageInfo.endCursor' <<<"$page")")
    done
fi

jq --argjson board "$board" --arg agent_field "$AGENT_FIELD" --arg repo "$REPO" --argjson wanted "$wanted_columns" --arg marker "$RANKED_MARKER" '
    def column: (.status.name // "") | '"$JQ_STRIP_PREFIX"';
    def key: "\(.repository.nameWithOwner)#\(.number)";
    (map(select(.content.number != null) | {key: (.content | key), value: (column | if . == "" then null else . end)}) | from_entries) as $columns
    | {board: $board, issues: [
        .[] | select(.content.repository.nameWithOwner == $repo and (.content.state == "OPEN" or ($board != null and (column | ascii_downcase) == "done"))
                     and ($board == null or (column | ascii_downcase | IN($wanted[]))))
        | .content as $c
        | {number: $c.number, title: $c.title, closedAt: $c.closedAt, column: (column | if . == "" then null else . end), labels: [$c.labels.nodes[].name],
           agent: ([$c.issueFieldValues.nodes[] | select(.field.name? == $agent_field) | .name] | first),
           openPrs: [$c.closedByPullRequestsReferences.nodes[] | select(.state == "OPEN") | .number],
           hasAcceptance: ($c.body | test("acceptance criteria"; "i")),
           ranked: (($c.comments.nodes // []) | any(.body | contains($marker))),
           blockedBy: [$c.blockedBy.nodes[] | {number, state, status: $columns[key]}
                       + (if .repository.nameWithOwner != $repo then {repo: .repository.nameWithOwner} else {} end)],
           blocking: [$c.blocking.nodes[] | if .repository.nameWithOwner == $repo then .number else "\(.repository.nameWithOwner)#\(.number)" end]}]}' <<<"$items"
