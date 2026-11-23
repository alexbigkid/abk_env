#!/usr/bin/env bash

#------------------------------------------------------------------------------
# review-state.sh - show the review state of the open pull request of an issue.
# Needs: gh (scope: repo), jq. Repo from the current directory or GH_REPO.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill, review-lib.sh is next to this script
source "$(dirname "$0")/../../project-board/scripts/lib.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/review-lib.sh"

usage() {
    cat <<USAGE
usage: review-state.sh <issue-number>
Prints, as JSON, the open pull request that closes the issue and where its review stands:
{"pr", "url", "branch", "base", "headSha", "id", "mergeable": MERGEABLE | CONFLICTING | UNKNOWN,
 "round": <reviews of the reviewer so far>, "max": $MAX_REVIEW_ROUNDS, "capped": <round >= max>, "lastReviewAt",
 "handledComment": the newest "$HANDLED_MARKER" comment of the coder, found by its hidden tag (null if none), "handledAt",
 "handledIsNew": <the comment is newer than the last review; false = the coder did not answer this round>,
 "unresolvedThreads": <number>}
Rounds are counted by the hidden tag at the end of the reviewer's reviews, not by their title.
No open pull request: {"pr": null}. Cost: 1 GraphQL request without a PR, otherwise 2.
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -eq 1 ] || usage_error
require_issue_numbers "$1"
resolve_repo
load_pr_state "$1"
