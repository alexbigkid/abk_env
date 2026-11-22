#!/usr/bin/env bash

#------------------------------------------------------------------------------
# board.sh - GitHub project board and Agent issue field helper for the
# issue-workflow agents (triager, coder, reviewer, tester).
#
# Needs: gh (scopes: repo, project, read:user), jq.
# Repo is taken from the current directory (or GH_REPO).
# Set PROJECT_NUMBER when an issue is on more than one board.
#------------------------------------------------------------------------------
set -euo pipefail

API_VERSION="X-GitHub-Api-Version: 2022-11-28"
AGENT_FIELD="Agent"

usage() {
    cat <<USAGE
usage: board.sh <command> <issue-number> [args]
  info    <n>                         show board fields and the current Agent
  move    <n> <status>                move to a Status column (Triage|Todo|Doing|Review|Testing|Done), clears Agent
  set     <n> <field> <value> [--if-empty]   set Priority, Size, Estimate, Start date, End date ("today" allowed)
  claim   <n> <agent>                 set the Agent issue field (Triager|Coder|Reviewer|Tester)
  release <n>                         clear the Agent issue field
  add     <n>                         add the issue to the board (needs PROJECT_NUMBER) in Triage
Without a board, board commands print "SKIPPED: ..." and exit 0.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) || die "cannot determine the repository"
OWNER=${REPO%%/*}
REPO_NAME=${REPO##*/}

# Load the board item of an issue into globals, return 1 when the issue is on no board.
# Anything but a valid API answer is an error, never "no board".
load_item() {
    local issue=$1 nodes
    # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
    nodes=$(gh api graphql -F owner="$OWNER" -F name="$REPO_NAME" -F n="$issue" -f query='
        query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){issue(number:$n){
          projectItems(first:20){nodes{id
            project{id number owner{... on User{login} ... on Organization{login}}}
            fieldValues(first:30){nodes{
              ... on ProjectV2ItemFieldSingleSelectValue{name field{... on ProjectV2FieldCommon{name}}}
              ... on ProjectV2ItemFieldDateValue{date field{... on ProjectV2FieldCommon{name}}}
              ... on ProjectV2ItemFieldNumberValue{number field{... on ProjectV2FieldCommon{name}}}
              ... on ProjectV2ItemFieldTextValue{text field{... on ProjectV2FieldCommon{name}}}}}}}}}}' \
        -q '.data.repository.issue.projectItems.nodes') || die "cannot read board data of issue #$issue (API error or rate limit)"
    jq -e 'type == "array"' <<<"$nodes" >/dev/null 2>&1 || die "unexpected API answer for issue #$issue (not a board answer)"
    local item
    item=$(jq -c --arg p "${PROJECT_NUMBER:-}" '[.[] | select($p == "" or (.project.number|tostring) == $p)] | first // empty' <<<"$nodes")
    [ -n "$item" ] || return 1
    ITEM_ID=$(jq -r .id <<<"$item")
    PROJECT_ID=$(jq -r .project.id <<<"$item")
    PROJECT_NUM=$(jq -r .project.number <<<"$item")
    PROJECT_OWNER=$(jq -r .project.owner.login <<<"$item")
    ITEM_VALUES=$(jq -c '.fieldValues.nodes' <<<"$item")
    FIELDS=$(gh project field-list "$PROJECT_NUM" --owner "$PROJECT_OWNER" --format json) || die "cannot read fields of project #$PROJECT_NUM"
}

# Print the current value of a project field of the loaded item (empty when unset).
get_value() {
    jq -r --arg f "$1" '.[] | select(.field.name? and (.field.name | ascii_downcase) == ($f | ascii_downcase)) | .name // .date // .number // .text // empty' <<<"$ITEM_VALUES"
}

# Set a project field by name, resolving field and option ids at runtime.
set_field() {
    local issue=$1 name=$2 value=$3 if_empty=${4:-}
    local field type id
    field=$(jq -c --arg n "$name" '[.fields[] | select((.name | ascii_downcase) == ($n | ascii_downcase))] | first // empty' <<<"$FIELDS")
    [ -n "$field" ] || die "field '$name' not found on project #$PROJECT_NUM"
    type=$(jq -r .type <<<"$field")
    id=$(jq -r .id <<<"$field")

    if [ "$if_empty" = "--if-empty" ] && [ -n "$(get_value "$name")" ]; then
        echo "kept: $name already set on #$issue"
        return 0
    fi

    local flag=() v
    if [ "$type" = "ProjectV2SingleSelectField" ]; then
        v=$(jq -r --arg v "$value" '[.options[] | select((.name | sub("^[^A-Za-z0-9]+"; "") | ascii_downcase) == ($v | ascii_downcase))] | first | .id // empty' <<<"$field")
        [ -n "$v" ] || die "option '$value' not found in '$name' (options: $(jq -r '[.options[].name] | join(", ")' <<<"$field"))"
        flag=(--single-select-option-id "$v")
    elif [ "$value" = "today" ] || [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        [ "$value" = "today" ] && value=$(date +%F)
        flag=(--date "$value")
    elif [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        flag=(--number "$value")
    else
        flag=(--text "$value")
    fi
    gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$id" "${flag[@]}" >/dev/null
    echo "set: $name = $value on #$issue"
}

# Print the Agent issue field definition as JSON, or fail with a hint.
agent_field_json() {
    local owner_type path out field
    owner_type=$(gh api "users/$OWNER" -q .type)
    if [ "$owner_type" = "Organization" ]; then path="/orgs/$OWNER/issue-fields"; else path="/user/issue-fields"; fi
    out=$(gh api "$path" -H "$API_VERSION" 2>&1) || die "cannot read issue fields ($path). Missing 'read:user' scope? Run: gh auth refresh -h github.com -s read:user"
    field=$(jq -c --arg f "$AGENT_FIELD" '[.[] | select(.name == $f)] | first // empty' <<<"$out")
    [ -n "$field" ] || die "issue field '$AGENT_FIELD' not found (Settings > Issue fields)"
    echo "$field"
}

cmd_claim() {
    local issue=$1 agent=$2 field
    field=$(agent_field_json)
    jq -e --arg a "$agent" '.options[] | select((.name | ascii_downcase) == ($a | ascii_downcase))' <<<"$field" >/dev/null ||
        die "agent '$agent' not an option (options: $(jq -r '[.options[].name] | join(", ")' <<<"$field"))"
    local name
    name=$(jq -r --arg a "$agent" '.options[] | select((.name | ascii_downcase) == ($a | ascii_downcase)) | .name' <<<"$field")
    jq -n --argjson id "$(jq .id <<<"$field")" --arg v "$name" '{issue_field_values: [{field_id: $id, value: $v}]}' |
        gh api -X POST "/repos/$REPO/issues/$issue/issue-field-values" -H "$API_VERSION" --input - >/dev/null
    echo "claimed: #$issue Agent = $name"
}

cmd_release() {
    local issue=$1 field
    field=$(agent_field_json)
    gh api -X DELETE "/repos/$REPO/issues/$issue/issue-field-values/$(jq .id <<<"$field")" -H "$API_VERSION" >/dev/null 2>&1 || true
    echo "released: #$issue Agent cleared"
}

cmd_move() {
    local issue=$1 status=$2
    if load_item "$issue"; then
        set_field "$issue" Status "$status"
    else
        echo "SKIPPED: #$issue is not on a project board, column not changed"
    fi
    (cmd_release "$issue") || echo "WARN: Agent field not released" >&2
}

cmd_set() {
    local issue=$1
    load_item "$issue" || { echo "SKIPPED: #$issue is not on a project board, '$2' not set"; return 0; }
    set_field "$issue" "$2" "$3" "${4:-}"
}

cmd_add() {
    local issue=$1
    [ -n "${PROJECT_NUMBER:-}" ] || die "set PROJECT_NUMBER to add an issue to a board"
    gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "https://github.com/$REPO/issues/$issue" >/dev/null
    load_item "$issue" || die "issue #$issue was not added to project #$PROJECT_NUMBER"
    set_field "$issue" Status Triage
}

cmd_info() {
    local issue=$1 field
    if load_item "$issue"; then
        echo "board: project #$PROJECT_NUM ($PROJECT_OWNER)"
        for field in Status Priority Size Estimate "Start date" "End date"; do
            echo "$field: $(get_value "$field")"
        done
    else
        echo "board: none (issue is on no project board)"
    fi
    echo "Agent: $(gh api "/repos/$REPO/issues/$issue/issue-field-values" -H "$API_VERSION" -q '[.[] | select(.issue_field_name == "'"$AGENT_FIELD"'") | .single_select_option.name] | first // ""' 2>/dev/null || true)"
}

CMD=${1:-}
case "$CMD" in
    info)    [ $# -eq 2 ] || { usage; exit 1; }; cmd_info "$2" ;;
    move)    [ $# -eq 3 ] || { usage; exit 1; }; cmd_move "$2" "$3" ;;
    set)     [ $# -ge 4 ] || { usage; exit 1; }; cmd_set "$2" "$3" "$4" "${5:-}" ;;
    claim)   [ $# -eq 3 ] || { usage; exit 1; }; cmd_claim "$2" "$3" ;;
    release) [ $# -eq 2 ] || { usage; exit 1; }; cmd_release "$2" ;;
    add)     [ $# -eq 2 ] || { usage; exit 1; }; cmd_add "$2" ;;
    --help|-h) usage ;;
    *)       usage; exit 1 ;;
esac
