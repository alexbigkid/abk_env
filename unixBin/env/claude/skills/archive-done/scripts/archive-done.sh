#!/usr/bin/env bash

#------------------------------------------------------------------------------
# archive-done.sh - keep the Done column of the project board small: issues closed
# in an earlier month move to Done-<year>-<month>, at a new year the monthly
# columns of the previous year collapse into Done-<year>.
#
# Needs: gh (scope: project), jq. Repo from the current directory (git remote
# "origin") or GH_REPO. GraphQL only; the number of requests does not grow with
# the number of issues (items are read 100 per page, all moves go in one request).
# ARCHIVE_TODAY (a UTC date, YYYY-MM-DD) replaces the current date for tests.
#
# Safety rule: removing a column that still holds an issue clears the Status of
# every issue in it. So a monthly column is removed only after its issues were
# moved and a fresh read of the board shows it empty (see SKILL.md).
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill
source "$(dirname "$0")/../../project-board/scripts/lib.sh"

STATUS_FIELD="Status"
DONE_COLUMN="Done"
NEW_COLUMN_COLOR="GRAY"
PAGE_SIZE=100

usage() {
    cat <<USAGE
usage: archive-done.sh [--dry-run]
  Moves issues closed in an earlier month from $DONE_COLUMN to $DONE_COLUMN-<year>-<month> (column created when missing);
  at a new year the monthly columns of the previous year collapse into $DONE_COLUMN-<year>.
  --dry-run   print what would happen, change nothing
  ARCHIVE_TODAY=YYYY-MM-DD replaces the current UTC date (tests).
Without a board it prints "SKIPPED: ..." and exits 0.
USAGE
}

# The jq definitions shared by the programs below: names of the archive columns and their order key.
JQ_DEFS='
def strip: sub("^[^A-Za-z0-9]+"; "");
def is_archive: test("^Done-[0-9]{4}(-[0-9]{2})?$");
def is_month: test("^Done-[0-9]{4}-[0-9]{2}$");
def key: .[5:] | if length == 4 then . + "-00" else . end;'

# Read the board (the project linked to the repo) into BOARD: {id, number, fieldId, options, items}; return 1 when there is none.
read_board() {
    local raw count cursor="" page items="[]" has_next
    # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
    raw=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){projectsV2(first:5){nodes{id number field(name:"'"$STATUS_FIELD"'"){... on ProjectV2SingleSelectField{id options{id name color description}}}}}}}')
    count=$(jq '.data.repository.projectsV2.nodes | length' <<<"$raw")
    [ "$count" -ne 0 ] || return 1
    [ "$count" -eq 1 ] || die "$REPO has $count linked project boards, cannot choose one"
    BOARD=$(jq -c '.data.repository.projectsV2.nodes[0] | {id, number, fieldId: .field.id,
        options: [.field.options[]? | {id, name, color, description: (.description // "")}]}' <<<"$raw")
    [ "$(jq -r '.fieldId // empty' <<<"$BOARD")" ] || die "the board has no single-select field '$STATUS_FIELD'"
    has_next=true
    while [ "$has_next" = "true" ]; do
        page=$(gql -f query='query{node(id:'"$(gql_string "$(jq -r .id <<<"$BOARD")")"'){... on ProjectV2{items(first:'"$PAGE_SIZE"''"${cursor:+, after:$(gql_string "$cursor")}"'){pageInfo{hasNextPage endCursor}
            nodes{id content{... on Issue{number state closedAt}}
            fieldValues(first:20){nodes{... on ProjectV2ItemFieldSingleSelectValue{name field{... on ProjectV2FieldCommon{name}}} ... on ProjectV2ItemFieldDateValue{date field{... on ProjectV2FieldCommon{name}}}}}}}}}}')
        items=$(jq -c --argjson acc "$items" --arg s "$STATUS_FIELD" '$acc + [.data.node.items.nodes[] | {id, issue: .content.number, state: .content.state, closedAt: .content.closedAt,
            status: ([.fieldValues.nodes[] | select(.field.name == $s)] | first | .name),
            endDate: ([.fieldValues.nodes[] | select(.field.name == "End date")] | first | .date)}]' <<<"$page")
        has_next=$(jq -r '.data.node.items.pageInfo.hasNextPage' <<<"$page")
        cursor=$(jq -r '.data.node.items.pageInfo.endCursor // empty' <<<"$page")
    done
    BOARD=$(jq -c --argjson items "$items" '. + {items: $items}' <<<"$BOARD")
}

# Print the plan for the board on stdin: {moves, create, final, changed}.
make_plan() {
    jq -c --arg today "$TODAY" "$JQ_DEFS"'
    ($today[0:4]) as $cy | ($today[0:7]) as $cm
    | def target($d): if $d[0:4] < $cy then "Done-" + $d[0:4] elif $d[0:7] < $cm then "Done-" + $d[0:7] else null end;
    . as $b
    | ($b.options | map(.name)) as $names
    | [ $b.items[] | select(.status != null) | (.status | strip) as $s
        | if $s == "'"$DONE_COLUMN"'" then
              ((.closedAt // .endDate // "")[0:10]) as $d
              | {item: ., to: (if $d == "" then null else target($d) end)}
          elif ($s | is_month) and ($s[5:9] < $cy) then {item: ., to: ("Done-" + $s[5:9])}
          else empty end
        | select(.to != null) | {item: .item.id, issue: .item.issue, from: .item.status, to: .to} ] as $moves
    | ([$moves[].to] | unique - $names) as $create
    | ($b.options | map(select(.name | is_archive)) + ($create | map({name: ., color: "'"$NEW_COLUMN_COLOR"'", description: ""}))
        | sort_by(.name | key) | reverse) as $archive
    | [ $b.options[] | select(.name | is_archive | not) | ., (select((.name | strip) == "'"$DONE_COLUMN"'") | $archive[]) ] as $final
    | {moves: $moves, create: $create, final: $final, changed: (($final | map(.name)) != $names)}'
}

# Send the complete option list (the argument, JSON) to the board and set OPTIONS to the options the API answers with.
update_options() {
    local body
    # shellcheck disable=SC2016  # $input is a GraphQL variable
    body=$(jq -cn --arg field "$(jq -r .fieldId <<<"$BOARD")" --argjson options "$1" '{
        query: "mutation($input: UpdateProjectV2FieldInput!){updateProjectV2Field(input:$input){projectV2Field{... on ProjectV2SingleSelectField{options{id name color description}}}}}",
        variables: {input: {fieldId: $field, singleSelectOptions: $options}}}')
    OPTIONS=$(gql --input - <<<"$body" | jq -c '.data.updateProjectV2Field.projectV2Field.options')
    [ "$OPTIONS" != "null" ] || die "unexpected API answer to the column update"
}

# Move the issues of the plan (JSON on stdin is the plan) in one request; OPTIONS holds the column ids.
move_items() {
    local mutation
    mutation=$(jq -r --arg p "$(jq -r .id <<<"$BOARD")" --arg f "$(jq -r .fieldId <<<"$BOARD")" --argjson o "$OPTIONS" '
        "mutation{" + ([.moves | to_entries[] | .key as $k | .value as $m | ([$o[] | select(.name == $m.to) | .id] | first) as $id
            | " m\($k): updateProjectV2ItemFieldValue(input:{projectId: \($p | @json), itemId: \($m.item | @json), fieldId: \($f | @json), value: {singleSelectOptionId: \($id | @json)}}){clientMutationId}"] | join("")) + " }"' <<<"$1")
    gql -f query="$mutation" >/dev/null
}

# Fail when an issue changed its state (BEFORE and BOARD are the two reads of the board).
verify_states() {
    local problem
    problem=$(jq -r --argjson before "$BEFORE" '
        . as $after
        | [$before.items[] | select(.issue != null) | . as $b | ($after.items[] | select(.id == $b.id) | select(.state != $b.state) | "#\($b.issue) changed its state from \($b.state) to \(.state)")]
        | first // empty' <<<"$BOARD")
    [ -z "$problem" ] || die "$problem; stopped, nothing removed"
}

# Fail when a moved issue is not in its new column (the plan is the argument).
verify_moves() {
    local problem
    problem=$(jq -r --argjson plan "$1" '
        . as $after | [$plan.moves[] | . as $m | select(([$after.items[] | select(.id == $m.item and .status == $m.to)] | length) == 0) | "#\($m.issue) is not in \($m.to)"] | first // empty' <<<"$BOARD")
    [ -z "$problem" ] || die "$problem; stopped, nothing removed"
}

# Print the monthly columns of a previous year of the board in BOARD.
old_month_columns() {
    jq -r "$JQ_DEFS"' .options[] | .name | select(is_month and (.[5:9] < "'"${TODAY:0:4}"'"))' <<<"$BOARD"
}

# Print the number of items in the column.
column_size() { jq -r --arg c "$1" '[.items[] | select(.status == $c)] | length' <<<"$BOARD"; }

main() {
    local dry_run="" plan column size candidates removal moved
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --dry-run) dry_run=1 ;;
        "") ;;
        *) usage_error ;;
    esac
    [ $# -le 1 ] || usage_error
    TODAY=${ARCHIVE_TODAY:-$(date -u +%F)}
    [[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "ARCHIVE_TODAY must be a date (YYYY-MM-DD), got '$TODAY'"
    resolve_repo
    read_board || { echo "SKIPPED: $REPO has no linked project board, nothing archived"; return 0; }
    BEFORE=$BOARD
    jq -e --arg d "$DONE_COLUMN" '.options | map(.name | sub("^[^A-Za-z0-9]+"; "")) | index($d)' <<<"$BOARD" >/dev/null || die "the board has no '$DONE_COLUMN' column"
    plan=$(make_plan <<<"$BOARD")
    candidates=$(old_month_columns)

    if [ -n "$dry_run" ]; then
        jq -r '(.create[] | "would create column: \(.)"), (.moves[] | "would move: #\(.issue) \(.from) -> \(.to)")' <<<"$plan"
        for column in $candidates; do echo "would remove column: $column (when empty)"; done
        [ "$(jq '(.create | length) + (.moves | length)' <<<"$plan")" -gt 0 ] || [ -n "$candidates" ] || echo "nothing to archive"
        return 0
    fi

    if [ "$(jq -r .changed <<<"$plan")" = "true" ]; then
        update_options "$(jq -c .final <<<"$plan")"
        jq -r '.create[] | "created column: \(.)"' <<<"$plan"
    else
        OPTIONS=$(jq -c .options <<<"$BOARD")
    fi
    moved=$(jq '.moves | length' <<<"$plan")
    if [ "$moved" -gt 0 ]; then
        move_items "$plan"
        jq -r '.moves[] | "moved: #\(.issue) \(.from) -> \(.to)"' <<<"$plan"
    fi
    if [ "$moved" -eq 0 ] && [ -z "$candidates" ]; then
        [ "$(jq '.create | length' <<<"$plan")" -gt 0 ] || [ "$(jq -r .changed <<<"$plan")" = "true" ] || echo "nothing to archive"
        return 0
    fi

    read_board || die "the board disappeared"
    verify_states
    removal=""
    for column in $(old_month_columns); do
        size=$(column_size "$column")
        [ "$size" -eq 0 ] || die "column $column still holds $size issue(s); stopped, nothing removed"
        removal+="$column"$'\n'
    done
    verify_moves "$plan"
    [ -n "$removal" ] || return 0
    update_options "$(jq -c --arg r "$removal" '.options | map(select(.name as $n | ($r | split("\n") | index($n)) | not))' <<<"$BOARD")"
    for column in $removal; do echo "removed column: $column"; done
}

main "$@"
