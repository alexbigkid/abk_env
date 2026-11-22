#!/usr/bin/env bash

#------------------------------------------------------------------------------
# blockers.sh - read, add and remove "blocked by" relationships between issues.
#
# Needs: gh (scope: repo), jq. Repo from the current directory (git remote
# "origin") or GH_REPO.
# API cost per command: 1 GraphQL query for all issues involved, plus at most
# 1 GraphQL request with all the changes. No REST calls.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh is next to this script
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<USAGE
usage: blockers.sh <command> <issue-number> [<blocker-number>...]
  list   <n>                      show what <n> is blocked by (number, state, title)
  add    <n> <blocker>...         make <n> blocked by each blocker (kept if it already exists)
  remove <n> <blocker>...         remove the relationship (kept if it does not exist)
add refuses a self-link and a direct cycle (the blocker is already blocked by <n>).
USAGE
}

# Read the given issues and their blockers in ONE query into STATE (JSON).
load_blockers() {
    local number selections="" raw
    require_issue_numbers "$@"
    for number in "$@"; do
        case " $selections " in *" i$number:"*) continue ;; esac
        selections+=" i$number: issue(number:$number){ id number blockedBy(first:50){nodes{id number state title}} }"
    done
    # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
    raw=$(gql -f owner="$OWNER" -f name="$REPO_NAME" -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){'"$selections"'}}')
    STATE=$(jq -c '[.data.repository | to_entries[] | .value | {number, id, blockedBy: [.blockedBy.nodes[] | {number, id, state, title}]}]' <<<"$raw") ||
        die "unexpected API answer"
}

# Print the node id of an issue.
node_id() { jq -r --argjson n "$1" 'first(.[] | select(.number == $n)) | .id' <<<"$STATE"; }

# Print whether issue $1 is blocked by issue $2 (yes or no).
is_blocked_by() { jq -r --argjson n "$1" --argjson b "$2" 'first(.[] | select(.number == $n)) | if any(.blockedBy[]; .number == $b) then "yes" else "no" end' <<<"$STATE"; }

# Show what an issue is blocked by.
cmd_list() {
    load_blockers "$1"
    jq -r --argjson n "$1" 'first(.[] | select(.number == $n)) | "#\($n) is blocked by: " + (if (.blockedBy | length) == 0 then "nothing" else (.blockedBy | map("#\(.number) (\(.state | ascii_downcase), \(.title))") | join("; ")) end)' <<<"$STATE"
}

# Make an issue blocked by the given blockers, in one request.
cmd_add() {
    local issue=$1 blocker
    shift
    load_blockers "$issue" "$@"
    for blocker in "$@"; do
        [ "$blocker" != "$issue" ] || die "#$issue cannot be blocked by itself"
        if [ "$(is_blocked_by "$issue" "$blocker")" = "yes" ]; then
            MESSAGES+="kept: #$issue is already blocked by #$blocker"$'\n'
        elif [ "$(is_blocked_by "$blocker" "$issue")" = "yes" ]; then
            die "cycle: #$blocker is already blocked by #$issue"
        else
            queue_mutation "addBlockedBy(input:{issueId: $(gql_string "$(node_id "$issue")"), blockingIssueId: $(gql_string "$(node_id "$blocker")")}){clientMutationId}" \
                "linked: #$issue is blocked by #$blocker"
        fi
    done
    apply_mutations
}

# Remove the given blockers of an issue, in one request.
cmd_remove() {
    local issue=$1 blocker
    shift
    load_blockers "$issue" "$@"
    for blocker in "$@"; do
        if [ "$(is_blocked_by "$issue" "$blocker")" = "yes" ]; then
            queue_mutation "removeBlockedBy(input:{issueId: $(gql_string "$(node_id "$issue")"), blockingIssueId: $(gql_string "$(node_id "$blocker")")}){clientMutationId}" \
                "removed: #$issue is no longer blocked by #$blocker"
        else
            MESSAGES+="kept: #$issue is not blocked by #$blocker"$'\n'
        fi
    done
    apply_mutations
}

CMD=${1:-}
case "$CMD" in
    --help|-h)  usage; exit 0 ;;
    list)       [ $# -eq 2 ] || usage_error ;;
    add|remove) [ $# -ge 3 ] || usage_error ;;
    *)          usage_error ;;
esac
resolve_repo
case "$CMD" in
    list)   cmd_list "$2" ;;
    add)    shift; cmd_add "$@" ;;
    remove) shift; cmd_remove "$@" ;;
esac
