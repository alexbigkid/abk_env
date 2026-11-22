#!/usr/bin/env bash

#------------------------------------------------------------------------------
# board.sh - GitHub project board and Agent issue field helper for the
# issue-workflow agents (triager, coder, reviewer, tester).
#
# Needs: gh (scopes: repo, project, read:user), jq.
# Repo is taken from the current directory (or GH_REPO).
# The board is found from the issue itself; nothing to configure.
#
# Typical cost: 1 REST call for the repo and 1 GraphQL query for the board item
# with all its fields, plus 1 mutation or a few REST calls for the change.
# "add" needs a few more calls.
#------------------------------------------------------------------------------
set -euo pipefail

API_VERSION="X-GitHub-Api-Version: 2022-11-28"
AGENT_FIELD="Agent"
STATUS_FIELD="Status"
DEFAULT_STATUS="Triage"
BOARD_FIELDS=(Status Priority Size Estimate "Start date" "End date")
OWNER_TYPE_ORG="Organization"
IF_EMPTY_FLAG="--if-empty"
NO_VALUE_MESSAGE="Issue field value not found"
TODAY_KEYWORD="today"

usage() {
    cat <<USAGE
usage: board.sh <command> <issue-number> [args]
  info    <n>                         show board fields and the current Agent
  move    <n> <status>                move to a Status column (Triage|Todo|Doing|Review|Testing|Done), clears Agent
  set     <n> <field> <value> [$IF_EMPTY_FLAG]   Priority P0-P2, Size XS-XL, Estimate <number>, Start/End date (YYYY-MM-DD or $TODAY_KEYWORD)
  claim   <n> <agent>                 set the Agent issue field (Triager|Coder|Reviewer|Tester)
  release <n>                         clear the Agent issue field
  order   <n> [<n>...]                place the issues in this order at the top of their column (first = top)
  add     <n>                         add the issue to the repo's linked board in $DEFAULT_STATUS (kept if already on a board)
Without a board, board commands print "SKIPPED: ..." and exit 0.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Print the usage to stderr and exit 1 for a wrong call.
usage_error() { usage >&2; exit 1; }

# Print only the message of a failed gh call (the text after its last "gh: ").
api_error() { local m=${1##*gh: }; echo "${m##*$'\n'}"; }

# Resolve repository and owner type with one REST call.
resolve_repo() {
    local repo_path="{owner}/{repo}" info
    if [ -n "${GH_REPO:-}" ]; then repo_path=$GH_REPO; fi
    info=$(gh api "repos/$repo_path" -q '[.full_name, .owner.type] | @tsv') || die "cannot determine the repository"
    IFS=$'\t' read -r REPO OWNER_TYPE <<<"$info"
    OWNER=${REPO%%/*}
    REPO_NAME=${REPO##*/}
}

# Load the board item of an issue (fields and field values included) with one GraphQL call.
# Returns 1 only when the issue is on no matching board; any API problem is an error.
load_item() {
    local issue=$1 nodes item
    # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
    nodes=$(gh api graphql -F owner="$OWNER" -F name="$REPO_NAME" -F n="$issue" -f query='
        query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){issue(number:$n){
          projectItems(first:20){nodes{id
            project{id number owner{... on User{login} ... on Organization{login}}
              fields(first:50){nodes{__typename
                ... on ProjectV2FieldCommon{id name dataType}
                ... on ProjectV2SingleSelectField{options{id name}}}}}
            fieldValues(first:30){nodes{
              ... on ProjectV2ItemFieldSingleSelectValue{name field{... on ProjectV2FieldCommon{name}}}
              ... on ProjectV2ItemFieldDateValue{date field{... on ProjectV2FieldCommon{name}}}
              ... on ProjectV2ItemFieldNumberValue{number field{... on ProjectV2FieldCommon{name}}}
              ... on ProjectV2ItemFieldTextValue{text field{... on ProjectV2FieldCommon{name}}}}}}}}}}' \
        -q '.data.repository.issue.projectItems.nodes') || die "cannot read board data of issue #$issue (API error or rate limit)"
    jq -e 'type == "array"' <<<"$nodes" >/dev/null 2>&1 || die "unexpected API answer for issue #$issue (not a board answer)"

    nodes=$(jq -c '[.[] | select(. != null and .project != null)]' <<<"$nodes")
    jq -e 'length > 0' <<<"$nodes" >/dev/null || return 1
    item=$(jq -c '.[0]' <<<"$nodes")
    ITEM_ID=$(jq -r .id <<<"$item")
    PROJECT_ID=$(jq -r .project.id <<<"$item")
    PROJECT_NUM=$(jq -r .project.number <<<"$item")
    PROJECT_OWNER=$(jq -r .project.owner.login <<<"$item")
    FIELDS=$(jq -c '.project.fields.nodes' <<<"$item")
    ITEM_VALUES=$(jq -c '.fieldValues.nodes' <<<"$item")
}

# Print the current value of a project field of the loaded item (empty when unset).
get_value() {
    jq -r --arg f "$1" '.[] | select(.field.name? and (.field.name | ascii_downcase) == ($f | ascii_downcase)) | .name // .date // .number // .text // empty' <<<"$ITEM_VALUES"
}

# Set a project field by name; field and option ids come from the loaded board.
set_field() {
    local issue=$1 name=$2 value=$3 if_empty=${4:-}
    local field id data_type option
    field=$(jq -c --arg n "$name" '[.[] | select((.name // "" | ascii_downcase) == ($n | ascii_downcase))] | first // empty' <<<"$FIELDS")
    [ -n "$field" ] || die "field '$name' not found on project #$PROJECT_NUM"
    id=$(jq -r .id <<<"$field")
    data_type=$(jq -r .dataType <<<"$field")

    if [ "$if_empty" = "$IF_EMPTY_FLAG" ] && [ -n "$(get_value "$name")" ]; then
        echo "kept: $name already set on #$issue"
        return 0
    fi

    local flag=()
    case "$data_type" in
        SINGLE_SELECT)
            option=$(jq -r --arg v "$value" '[.options[] | select((.name | sub("^[^A-Za-z0-9]+"; "") | ascii_downcase) == ($v | ascii_downcase))] | first | .id // empty' <<<"$field")
            [ -n "$option" ] || die "option '$value' not found in '$name' (options: $(jq -r '[.options[].name] | join(", ")' <<<"$field"))"
            flag=(--single-select-option-id "$option") ;;
        DATE)
            if [ "$(tr '[:upper:]' '[:lower:]' <<<"$value")" = "$TODAY_KEYWORD" ]; then value=$(date +%F); fi
            [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "'$name' needs a date (YYYY-MM-DD or $TODAY_KEYWORD), got '$value'"
            flag=(--date "$value") ;;
        NUMBER)
            [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "'$name' needs a number, got '$value'"
            flag=(--number "$value") ;;
        TEXT)
            flag=(--text "$value") ;;
        *)
            die "field '$name' has unsupported type $data_type" ;;
    esac
    gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$id" "${flag[@]}" >/dev/null
    echo "set: $name = $value on #$issue"
}

# Print the Agent issue field definition as JSON, or fail with the API message.
agent_field_json() {
    local api_path out field
    if [ "$OWNER_TYPE" = "$OWNER_TYPE_ORG" ]; then api_path="/orgs/$OWNER/issue-fields"; else api_path="/user/issue-fields"; fi
    out=$(gh api "$api_path" -H "$API_VERSION" 2>&1) || {
        local hint=""
        if grep -qi "scope" <<<"$out"; then hint=" (a missing scope needs: gh auth refresh -h github.com -s read:user)"; fi
        die "cannot read issue fields from $api_path: $(api_error "$out")$hint"
    }
    field=$(jq -c --arg f "$AGENT_FIELD" '[.[] | select(.name == $f)] | first // empty' <<<"$out")
    [ -n "$field" ] || die "issue field '$AGENT_FIELD' not found (Settings > Issue fields)"
    echo "$field"
}

# Print the canonical option name of an issue field for a case-insensitive input, empty when unknown.
option_name() {
    jq -r --arg a "$2" '[.options[] | select((.name | ascii_downcase) == ($a | ascii_downcase)) | .name] | first // empty' <<<"$1"
}

cmd_claim() {
    local issue=$1 agent=$2 field name
    field=$(agent_field_json)
    name=$(option_name "$field" "$agent")
    [ -n "$name" ] || die "agent '$agent' not an option (options: $(jq -r '[.options[].name] | join(", ")' <<<"$field"))"
    jq -n --argjson id "$(jq .id <<<"$field")" --arg v "$name" '{issue_field_values: [{field_id: $id, value: $v}]}' |
        gh api -X POST "/repos/$REPO/issues/$issue/issue-field-values" -H "$API_VERSION" --input - >/dev/null
    echo "claimed: #$issue $AGENT_FIELD = $name"
}

cmd_release() {
    local issue=$1 field out
    field=$(agent_field_json)
    if out=$(gh api -X DELETE "/repos/$REPO/issues/$issue/issue-field-values/$(jq -r .id <<<"$field")" -H "$API_VERSION" 2>&1); then
        echo "released: #$issue $AGENT_FIELD cleared"
    elif grep -q "$NO_VALUE_MESSAGE" <<<"$out"; then
        echo "nothing to release: #$issue has no $AGENT_FIELD set"
    else
        die "cannot clear $AGENT_FIELD on #$issue: $(api_error "$out")"
    fi
}

cmd_move() {
    local issue=$1 column=$2
    if load_item "$issue"; then
        set_field "$issue" "$STATUS_FIELD" "$column"
    else
        echo "SKIPPED: #$issue is not on a project board, column not changed"
    fi
    cmd_release "$issue"
}

cmd_set() {
    local issue=$1
    load_item "$issue" || { echo "SKIPPED: #$issue is not on a project board, '$2' not set"; return 0; }
    set_field "$issue" "$2" "$3" "${4:-}"
}

cmd_add() {
    local issue=$1 projects count number owner
    if load_item "$issue"; then
        echo "kept: #$issue is already on project #$PROJECT_NUM, column unchanged"
        return 0
    fi
    # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
    projects=$(gh api graphql -F owner="$OWNER" -F name="$REPO_NAME" -f query='
        query($owner:String!,$name:String!){repository(owner:$owner,name:$name){projectsV2(first:5){nodes{number
          owner{... on User{login} ... on Organization{login}}}}}}' \
        -q '.data.repository.projectsV2.nodes') || die "cannot read the projects linked to $REPO"
    count=$(jq 'length' <<<"$projects")
    if [ "$count" -eq 0 ]; then
        echo "SKIPPED: $REPO has no linked project board, #$issue not added"
        return 0
    fi
    [ "$count" -eq 1 ] || die "$REPO has $count linked project boards, cannot choose one"
    number=$(jq -r '.[0].number' <<<"$projects")
    owner=$(jq -r '.[0].owner.login' <<<"$projects")
    gh project item-add "$number" --owner "$owner" --url "https://github.com/$REPO/issues/$issue" >/dev/null
    load_item "$issue" || die "issue #$issue was not added to project #$number"
    set_field "$issue" "$STATUS_FIELD" "$DEFAULT_STATUS"
}

cmd_order() {
    local issue after_id="" args
    for issue in "$@"; do
        if ! load_item "$issue"; then
            [ -n "$after_id" ] || { echo "SKIPPED: #$issue is not on a project board, order not changed"; return 0; }
            die "issue #$issue is not on the board, order only partly applied"
        fi
        args=(-f p="$PROJECT_ID" -f i="$ITEM_ID")
        if [ -n "$after_id" ]; then args+=(-f a="$after_id"); fi
        # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
        gh api graphql "${args[@]}" -f query='
            mutation($p:ID!,$i:ID!,$a:ID){updateProjectV2ItemPosition(input:{projectId:$p,itemId:$i,afterId:$a}){items(first:1){nodes{id}}}}' >/dev/null ||
            die "cannot place #$issue (API error or rate limit)"
        after_id=$ITEM_ID
    done
    echo "ordered: $(printf '#%s ' "$@")"
}

cmd_info() {
    local issue=$1 field agent
    if load_item "$issue"; then
        echo "board: project #$PROJECT_NUM ($PROJECT_OWNER)"
        for field in "${BOARD_FIELDS[@]}"; do
            echo "$field: $(get_value "$field")"
        done
    else
        echo "board: none (issue is on no project board)"
    fi
    agent=$(gh api "/repos/$REPO/issues/$issue/issue-field-values" -H "$API_VERSION" \
        -q '[.[] | select(.issue_field_name == "'"$AGENT_FIELD"'") | .single_select_option.name] | first // ""') ||
        die "cannot read issue field values of #$issue"
    echo "$AGENT_FIELD: $agent"
}

CMD=${1:-}
case "$CMD" in
    --help|-h|"") usage; exit 0 ;;
    info|release|add) [ $# -eq 2 ] || usage_error ;;
    order)            [ $# -ge 2 ] || usage_error ;;
    move|claim)       [ $# -eq 3 ] || usage_error ;;
    set)              if [ $# -ne 4 ] && ! { [ $# -eq 5 ] && [ "$5" = "$IF_EMPTY_FLAG" ]; }; then usage_error; fi ;;
    *)                usage_error ;;
esac
resolve_repo
case "$CMD" in
    info)    cmd_info "$2" ;;
    move)    cmd_move "$2" "$3" ;;
    set)     cmd_set "$2" "$3" "$4" "${5:-}" ;;
    claim)   cmd_claim "$2" "$3" ;;
    release) cmd_release "$2" ;;
    add)     cmd_add "$2" ;;
    order)   shift; cmd_order "$@" ;;
esac
