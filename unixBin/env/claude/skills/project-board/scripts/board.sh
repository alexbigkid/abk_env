#!/usr/bin/env bash

#------------------------------------------------------------------------------
# board.sh - GitHub project board and Agent issue field helper for the
# issue-workflow agents (triager, coder, reviewer, tester).
#
# Needs: gh (scopes: repo, project, read:user), jq. Repo from the current
# directory (git remote "origin") or GH_REPO. The board is found from the issue.
#
# API cost per command: 1 GraphQL query that reads everything, plus at most
# 1 GraphQL request with all the changes ("add" needs 2). No REST calls.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh is next to this script
source "$(dirname "$0")/lib.sh"

AGENT_FIELD="Agent"
STATUS_FIELD="Status"
DEFAULT_STATUS="Triage"
INFO_FIELDS=(Status Priority Size Estimate "Start date" "End date")
IF_EMPTY_FLAG="--if-empty"
TODAY_KEYWORD="today"

# GraphQL parts of the one query that reads everything.
ISSUE_PART='state
    issueFieldValues(first:10){nodes{... on IssueFieldSingleSelectValue{name field{... on IssueFieldSingleSelect{id name}}}}}
    projectItems(first:5){nodes{id project{id number} fieldValues(first:30){nodes{
      ... on ProjectV2ItemFieldSingleSelectValue{name field{... on ProjectV2FieldCommon{name}}}
      ... on ProjectV2ItemFieldDateValue{date field{... on ProjectV2FieldCommon{name}}}
      ... on ProjectV2ItemFieldNumberValue{number field{... on ProjectV2FieldCommon{name}}}
      ... on ProjectV2ItemFieldTextValue{text field{... on ProjectV2FieldCommon{name}}}}}}}'
PROJECTS_PART='projectsV2(first:5){nodes{id number fields(first:50){nodes{__typename
      ... on ProjectV2FieldCommon{id name dataType} ... on ProjectV2SingleSelectField{options{id name}}}}}}'
AGENT_PART='owner{__typename
      ... on User{issueFields(first:20){nodes{... on IssueFieldSingleSelect{id name options{id name}}}}}
      ... on Organization{issueFields(first:20){nodes{... on IssueFieldSingleSelect{id name options{id name}}}}}}'

usage() {
    cat <<USAGE
usage: board.sh <command> ...
  info    <n>                              show board fields and the current Agent
  move    <n> <status> [Field=Value...]    move to a Status column (Triage|Todo|Doing|Review|Testing|Done), set more
                                           fields in the same request (Field:=Value only when empty), clear Agent
  apply                                    read a plan from stdin, one issue per line: <n>|Field=Value|Field=Value|...[|$IF_EMPTY_FLAG]
                                           (Status=<column> also clears the Agent; use Field:=Value, not $IF_EMPTY_FLAG, on lines with a Status); all issues in one request
  set     <n> Field=Value... [$IF_EMPTY_FLAG]  Priority=P0-P2, Size=XS-XL, Estimate=<number>, "Start date=YYYY-MM-DD|$TODAY_KEYWORD", "End date=..."; Field:=Value sets the field only when it is empty
  claim   <agent> <n>...                   set the Agent issue field (Triager|Coder|Reviewer|Tester)
  release <n>...                           clear the Agent issue field
  order   <n>...                           put the issues in this order (relative order within each column)
  add     <n>                              add the issue to the repo's linked board in $DEFAULT_STATUS (kept if already on a board)
Without a board, board commands print "SKIPPED: ..." and exit 0.
USAGE
}

# Read everything about the given issues in ONE query into STATE (JSON); WITH_AGENT_FIELD=1 adds the Agent field definition.
load_issues() {
    local number selections="" agent_part="" raw
    require_issue_numbers "$@"
    for number in "$@"; do
        case " $selections " in *" i$number:"*) continue ;; esac
        selections+=" i$number: issue(number:$number){ id number $ISSUE_PART }"
    done
    if [ "${WITH_AGENT_FIELD:-}" = "1" ]; then agent_part=$AGENT_PART; fi
    # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
    raw=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){'"$agent_part $PROJECTS_PART $selections"'}}')
    STATE=$(jq -c --arg agent "$AGENT_FIELD" '
        .data.repository as $r | {
          agentField: ([($r.owner.issueFields.nodes // [])[] | select(.name == $agent)] | first),
          projects: [$r.projectsV2.nodes[] | {id, number, fields: [.fields.nodes[] | {id, name, dataType, options}]}],
          issues: [$r | to_entries[] | select(.key | test("^i[0-9]+$")) | .value | {number, id, state,
            agent: ([.issueFieldValues.nodes[] | select(.field.name? == $agent)] | first | if . then {name, fieldId: .field.id} else null end),
            items: [.projectItems.nodes[] | {id, projectId: .project.id, values: .fieldValues.nodes}]}]}' <<<"$raw") ||
        die "unexpected API answer (not a board answer)"
}

# Print the loaded data (JSON) of one issue.
issue_json() { jq -c --argjson n "$1" '.issues[] | select(.number == $n)' <<<"$STATE"; }

# Select the board an issue is on (BOARD_ID, BOARD_NUMBER, BOARD_FIELDS_JSON); return 1 when it is on none.
select_board() {
    local project_id
    project_id=$(jq -r --argjson n "$1" '[.issues[] | select(.number == $n) | .items[].projectId] | first // empty' <<<"$STATE")
    [ -n "$project_id" ] || return 1
    use_project "$project_id"
}

# Make a linked project the selected board.
use_project() {
    BOARD_ID=$1
    BOARD_NUMBER=$(jq -r --arg p "$1" 'first(.projects[] | select(.id == $p)) | .number' <<<"$STATE")
    [ -n "$BOARD_NUMBER" ] || die "the project board of the issue is not linked to $REPO"
    BOARD_FIELDS_JSON=$(jq -c --arg p "$1" 'first(.projects[] | select(.id == $p)) | .fields' <<<"$STATE")
}

# Print the board item id of an issue on the selected board, empty when it is not on it.
item_id() { jq -r --argjson n "$1" --arg p "$BOARD_ID" 'first(.issues[] | select(.number == $n) | .items[] | select(.projectId == $p)) | .id' <<<"$STATE"; }

# Print the current value of a board field of an issue (empty when unset).
current_value() {
    jq -r --argjson n "$1" --arg p "$BOARD_ID" --arg f "$2" '
        first(.issues[] | select(.number == $n) | .items[] | select(.projectId == $p)) | [.values[]
        | select(.field.name? and (.field.name | ascii_downcase) == ($f | ascii_downcase)) | .name // .date // .number // .text // empty] | first // empty' <<<"$STATE"
}

# Queue setting a board field of an issue; field and option ids come from the loaded board.
queue_field() {
    local issue=$1 name=$2 value=$3 if_empty=${4:-}
    local field field_id data_type option literal
    field=$(jq -c --arg n "$name" 'first(.[] | select((.name | ascii_downcase) == ($n | ascii_downcase)))' <<<"$BOARD_FIELDS_JSON")
    [ -n "$field" ] || die "field '$name' not found on project #$BOARD_NUMBER"
    field_id=$(jq -r .id <<<"$field")
    data_type=$(jq -r .dataType <<<"$field")
    if [ "$if_empty" = "$IF_EMPTY_FLAG" ] && [ -n "$(current_value "$issue" "$name")" ]; then
        MESSAGES+="kept: $name already set on #$issue"$'\n'
        return 0
    fi
    case "$data_type" in
        SINGLE_SELECT)
            option=$(jq -c --arg v "$value" 'first(.options[] | select((.name | '"$JQ_STRIP_PREFIX"' | ascii_downcase) == ($v | ascii_downcase)))' <<<"$field")
            [ -n "$option" ] || die "option '$value' not found in '$name' (options: $(jq -r '[.options[].name] | join(", ")' <<<"$field"))"
            literal="{singleSelectOptionId: $(gql_string "$(jq -r .id <<<"$option")")}"
            value=$(jq -r '.name | '"$JQ_STRIP_PREFIX" <<<"$option") ;;
        DATE)
            if [ "$(tr '[:upper:]' '[:lower:]' <<<"$value")" = "$TODAY_KEYWORD" ]; then value=$(date +%F); fi
            [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "'$name' needs a date (YYYY-MM-DD or $TODAY_KEYWORD), got '$value'"
            literal="{date: $(gql_string "$value")}" ;;
        NUMBER)
            [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "'$name' needs a number, got '$value'"
            value=$(jq -rn --arg v "$value" '$v | tonumber')
            literal="{number: $value}" ;;
        TEXT)
            literal="{text: $(gql_string "$value")}" ;;
        *)
            die "field '$name' has unsupported type $data_type" ;;
    esac
    queue_mutation "updateProjectV2ItemFieldValue(input:{projectId: $(gql_string "$BOARD_ID"), itemId: $(gql_string "$(item_id "$issue")"), fieldId: $(gql_string "$field_id"), value: $literal}){clientMutationId}" \
        "set: $name = $value on #$issue"
}

# Queue clearing the Agent issue field of an issue (nothing when it is not set); once per issue.
queue_release() {
    local data agent_name field_id
    case " $RELEASED " in *" $1 "*) return 0 ;; esac
    RELEASED+=" $1"
    data=$(issue_json "$1")
    agent_name=$(jq -r '.agent.name // empty' <<<"$data")
    if [ -z "$agent_name" ]; then
        MESSAGES+="nothing to release: #$1 has no $AGENT_FIELD set"$'\n'
        return 0
    fi
    field_id=$(jq -r '.agent.fieldId' <<<"$data")
    queue_mutation "deleteIssueFieldValue(input:{issueId: $(gql_string "$(jq -r .id <<<"$data")"), fieldId: $(gql_string "$field_id")}){clientMutationId}" \
        "released: #$1 $AGENT_FIELD cleared"
}

# Split Field=Value arguments into queued field changes of an issue (Field:=Value sets only an empty field; the $IF_EMPTY_FLAG flag does that for all).
queue_pairs() {
    local issue=$1 pair name pair_if_empty if_empty="" pairs=()
    shift
    for pair in "$@"; do
        if [ "$pair" = "$IF_EMPTY_FLAG" ]; then if_empty=$IF_EMPTY_FLAG; else pairs+=("$pair"); fi
    done
    for pair in ${pairs[@]+"${pairs[@]}"}; do
        [[ "$pair" == *=* ]] || die "expected Field=Value, got '$pair'"
        name=${pair%%=*}
        pair_if_empty=$if_empty
        if [[ "$name" == *: ]]; then name=${name%:}; pair_if_empty=$IF_EMPTY_FLAG; fi
        queue_field "$issue" "$name" "${pair#*=}" "$pair_if_empty"
    done
}

# Show the board fields and the Agent of an issue.
cmd_info() {
    local field
    load_issues "$1"
    if select_board "$1"; then
        echo "board: project #$BOARD_NUMBER"
        for field in "${INFO_FIELDS[@]}"; do
            echo "$field: $(current_value "$1" "$field")"
        done
    else
        echo "board: none (issue is on no project board)"
    fi
    echo "$AGENT_FIELD: $(jq -r '.agent.name // ""' <<<"$(issue_json "$1")")"
}

# Queue the changes of one plan line: Field=Value pairs; setting the Status also clears the Agent.
plan_issue() {
    local issue=$1 pair has_status=""
    shift
    for pair in "$@"; do
        if [[ "$pair" == *=* ]] && [ "$(tr '[:upper:]' '[:lower:]' <<<"${pair%%=*}")" = "$(tr '[:upper:]' '[:lower:]' <<<"$STATUS_FIELD")" ]; then has_status=1; fi
    done
    if select_board "$issue"; then
        queue_pairs "$issue" "$@"
    else
        MESSAGES+="SKIPPED: #$issue is not on a project board, board fields not changed"$'\n'
    fi
    if [ -n "$has_status" ]; then queue_release "$issue"; fi
}

# Move one issue to a column, set more fields and clear the Agent, in one request.
cmd_move() {
    local issue=$1 column=$2
    shift 2
    load_issues "$issue"
    plan_issue "$issue" "$STATUS_FIELD=$column" "$@"
    apply_mutations
}

# Apply a plan read from stdin (one issue per line, fields separated by "|") to all its issues in one request.
cmd_apply() {
    local line rest part issue plan="" numbers=() fields
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        case "$line" in ""|"#"*) continue ;; esac
        plan+="$line"$'\n'
        numbers+=("${line%%|*}")
    done
    [ -n "$plan" ] || die "the plan on stdin is empty"
    load_issues "${numbers[@]}"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        issue=${line%%|*}
        fields=()
        rest=${line#"$issue"}
        while [ -n "$rest" ]; do
            rest=${rest#|}
            part=${rest%%|*}
            fields+=("$part")
            if [ "$part" = "$rest" ]; then rest=""; else rest=${rest#*|}; fi
        done
        plan_issue "$issue" ${fields[@]+"${fields[@]}"}
    done <<<"$plan"
    apply_mutations
}

# Set board fields of one issue (no column change, the Agent stays).
cmd_set() {
    local issue=$1
    shift
    load_issues "$issue"
    select_board "$issue" || { echo "SKIPPED: #$issue is not on a project board, nothing set"; return 0; }
    queue_pairs "$issue" "$@"
    apply_mutations
}

# Set the Agent issue field of one or more issues.
cmd_claim() {
    local agent=$1 issue option_id option_name
    shift
    WITH_AGENT_FIELD=1 load_issues "$@"
    [ "$(jq -r '.agentField | type' <<<"$STATE")" = "object" ] || die "issue field '$AGENT_FIELD' not found (Settings > Issue fields)"
    option_id=$(jq -r --arg a "$agent" 'first(.agentField.options[] | select((.name | ascii_downcase) == ($a | ascii_downcase))) | .id' <<<"$STATE")
    option_name=$(jq -r --arg a "$agent" 'first(.agentField.options[] | select((.name | ascii_downcase) == ($a | ascii_downcase))) | .name' <<<"$STATE")
    [ -n "$option_id" ] || die "agent '$agent' not an option (options: $(jq -r '[.agentField.options[].name] | join(", ")' <<<"$STATE"))"
    for issue in "$@"; do
        queue_mutation "setIssueFieldValue(input:{issueId: $(gql_string "$(jq -r .id <<<"$(issue_json "$issue")")"), issueFields: [{fieldId: $(gql_string "$(jq -r .agentField.id <<<"$STATE")"), singleSelectOptionId: $(gql_string "$option_id")}]}){clientMutationId}" \
            "claimed: #$issue $AGENT_FIELD = $option_name"
    done
    apply_mutations
}

# Clear the Agent issue field of one or more issues.
cmd_release() {
    local issue
    load_issues "$@"
    for issue in "$@"; do queue_release "$issue"; done
    apply_mutations
}

# Put the given issues in this order on the board.
cmd_order() {
    local issue after_id="" this_id seen=""
    for issue in "$@"; do
        case " $seen " in *" $issue "*) die "issue #$issue is listed twice" ;; esac
        seen+=" $issue"
    done
    load_issues "$@"
    select_board "$1" || { echo "SKIPPED: #$1 is not on a project board, order not changed"; return 0; }
    for issue in "$@"; do
        this_id=$(item_id "$issue")
        [ -n "$this_id" ] || die "issue #$issue is not on project #$BOARD_NUMBER, order not changed"
        queue_mutation "updateProjectV2ItemPosition(input:{projectId: $(gql_string "$BOARD_ID"), itemId: $(gql_string "$this_id")${after_id:+, afterId: $(gql_string "$after_id")}}){clientMutationId}" \
            "placed: #$issue"
        after_id=$this_id
    done
    apply_mutations
}

# Put an issue on the repo's linked board in the default column.
cmd_add() {
    local issue=$1 count issue_node new_item
    load_issues "$issue"
    if select_board "$issue"; then
        echo "kept: #$issue is already on project #$BOARD_NUMBER, column unchanged"
        return 0
    fi
    count=$(jq '.projects | length' <<<"$STATE")
    if [ "$count" -eq 0 ]; then
        echo "SKIPPED: $REPO has no linked project board, #$issue not added"
        return 0
    fi
    [ "$count" -eq 1 ] || die "$REPO has $count linked project boards, cannot choose one"
    use_project "$(jq -r '.projects[0].id' <<<"$STATE")"
    issue_node=$(jq -r .id <<<"$(issue_json "$issue")")
    new_item=$(gql -f query="mutation{ a: addProjectV2ItemById(input:{projectId: $(gql_string "$BOARD_ID"), contentId: $(gql_string "$issue_node")}){item{id}} }" | jq -r '.data.a.item.id')
    [ -n "$new_item" ] || die "issue #$issue was not added to project #$BOARD_NUMBER"
    # The new item has no values yet: queue the default column on it directly.
    STATE=$(jq -c --argjson n "$issue" --arg p "$BOARD_ID" --arg i "$new_item" '(.issues[] | select(.number == $n) | .items) += [{id: $i, projectId: $p, values: []}]' <<<"$STATE")
    queue_field "$issue" "$STATUS_FIELD" "$DEFAULT_STATUS"
    apply_mutations
}

CMD=${1:-}
case "$CMD" in
    --help|-h|"")  usage; exit 0 ;;
    info|add)      [ $# -eq 2 ] || usage_error ;;
    release|order) [ $# -ge 2 ] || usage_error ;;
    move|set|claim) [ $# -ge 3 ] || usage_error ;;
    apply)         [ $# -eq 1 ] || usage_error ;;
    *)             usage_error ;;
esac
resolve_repo
case "$CMD" in
    info)    cmd_info "$2" ;;
    move)    shift; cmd_move "$@" ;;
    set)     shift; cmd_set "$@" ;;
    claim)   shift; cmd_claim "$@" ;;
    release) shift; cmd_release "$@" ;;
    order)   shift; cmd_order "$@" ;;
    apply)   cmd_apply ;;
    add)     cmd_add "$2" ;;
esac
