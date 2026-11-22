#!/usr/bin/env bash

#------------------------------------------------------------------------------
# blockers.sh - read, add and remove "blocked by" relationships between issues.
#
# Needs: gh (scope: repo). Repo from the current directory or GH_REPO.
#------------------------------------------------------------------------------
set -euo pipefail

API_VERSION="X-GitHub-Api-Version: 2022-11-28"
ALREADY_LINKED_MESSAGE="has already been taken"

usage() {
    cat <<USAGE
usage: blockers.sh <command> <issue-number> [<blocker-number>...]
  list   <n>                      show what <n> is blocked by (number, state, title)
  add    <n> <blocker>...         make <n> blocked by each blocker (kept if it already exists)
  remove <n> <blocker>...         remove the relationship (kept if it does not exist)
add refuses a direct cycle (the blocker is already blocked by <n>).
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }
usage_error() { usage >&2; exit 1; }

# Print only the message of a failed gh call (the text after its last "gh: ").
api_error() { local m=${1##*gh: }; echo "${m##*$'\n'}"; }

# Print the numeric id of an issue (the relationships API needs ids, not numbers).
issue_id() { gh api "repos/$REPO_PATH/issues/$1" -q .id 2>/dev/null || die "cannot read issue #$1"; }

# Print the numbers of the issues that issue $1 is blocked by.
blocked_by_numbers() { gh api "repos/$REPO_PATH/issues/$1/dependencies/blocked_by" -H "$API_VERSION" -q '.[].number' 2>/dev/null || die "cannot read the blockers of #$1"; }

cmd_list() {
    gh api "repos/$REPO_PATH/issues/$1/dependencies/blocked_by" -H "$API_VERSION" \
        -q '"#'"$1"' is blocked by: " + (if length == 0 then "nothing" else (map("#\(.number) (\(.state), \(.title))") | join("; ")) end)' ||
        die "cannot read the blockers of #$1"
}

cmd_add() {
    local issue=$1 blocker blocker_id blockers_of_blocker out
    shift
    for blocker in "$@"; do
        blocker_id=$(issue_id "$blocker")
        blockers_of_blocker=$(blocked_by_numbers "$blocker")
        if grep -qx "$issue" <<<"$blockers_of_blocker"; then
            die "cycle: #$blocker is already blocked by #$issue"
        fi
        if out=$(gh api -X POST "repos/$REPO_PATH/issues/$issue/dependencies/blocked_by" -H "$API_VERSION" -F issue_id="$blocker_id" 2>&1); then
            echo "linked: #$issue is blocked by #$blocker"
        elif grep -q "$ALREADY_LINKED_MESSAGE" <<<"$out"; then
            echo "kept: #$issue is already blocked by #$blocker"
        else
            die "cannot link #$issue to #$blocker: $(api_error "$out")"
        fi
    done
}

cmd_remove() {
    local issue=$1 blocker blocker_id current
    shift
    current=$(blocked_by_numbers "$issue")
    for blocker in "$@"; do
        if grep -qx "$blocker" <<<"$current"; then
            blocker_id=$(issue_id "$blocker")
            gh api -X DELETE "repos/$REPO_PATH/issues/$issue/dependencies/blocked_by/$blocker_id" -H "$API_VERSION" >/dev/null ||
                die "cannot remove the relationship of #$issue to #$blocker"
            echo "removed: #$issue is no longer blocked by #$blocker"
        else
            echo "kept: #$issue is not blocked by #$blocker"
        fi
    done
}

CMD=${1:-}
case "$CMD" in
    --help|-h) usage; exit 0 ;;
    list)          [ $# -eq 2 ] || usage_error ;;
    add|remove)    [ $# -ge 3 ] || usage_error ;;
    *)             usage_error ;;
esac

REPO_PATH="{owner}/{repo}"
if [ -n "${GH_REPO:-}" ]; then REPO_PATH=$GH_REPO; fi

case "$CMD" in
    list)   cmd_list "$2" ;;
    add)    shift; cmd_add "$@" ;;
    remove) shift; cmd_remove "$@" ;;
esac
