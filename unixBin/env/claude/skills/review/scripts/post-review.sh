#!/usr/bin/env bash

#------------------------------------------------------------------------------
# post-review.sh - post ONE review with tagged findings on the open pull request of an issue.
# Needs: gh (scope: repo), jq. Repo from the current directory or GH_REPO.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill, review-lib.sh is next to this script
source "$(dirname "$0")/../../project-board/scripts/lib.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/review-lib.sh"

DRY_RUN_FLAG="--dry-run"
INLINE_REJECTED_PATTERN="diff|path|line|thread"
# shellcheck disable=SC2016  # $input is a GraphQL variable, not shell
MUTATION='mutation($input: AddPullRequestReviewInput!){addPullRequestReview(input:$input){pullRequestReview{id url}}}'

usage() {
    cat <<USAGE
usage: post-review.sh <issue-number> [$DRY_RUN_FLAG]      (the findings come as JSON on stdin)
{"summary": "<markdown summary of the review>",
 "findings": [{"tag": "must-fix" | "suggestion", "body": "<text>", "path": "<file>", "line": <n>}, ...]}
"path" and "line" go together; a finding without them is listed in the review body. Every comment
starts with its tag. The review is posted as a plain comment review (GitHub does not allow requesting
changes on a pull request of your own account), titled "$ROUND_MARKER <k> of $MAX_REVIEW_ROUNDS".
Refuses when no open pull request closes the issue or when $MAX_REVIEW_ROUNDS rounds are used up
(escalate to the user instead). If GitHub rejects an inline comment (a line outside the diff), the
whole review is posted once more with all findings in its body. $DRY_RUN_FLAG prints the request only.
USAGE
}

# Build the GraphQL request: mode "inline" puts located findings into threads, mode "body" lists all in the body.
build_request() {
    jq -nc --argjson state "$state" --argjson findings "$findings" --arg summary "$summary" --arg mode "$1" \
        --arg round_marker "$ROUND_MARKER" --arg mutation "$MUTATION" '
        def listed: "- [\(.tag)] " + (if has("path") then "`\(.path):\(.line)` " else "" end) + .body;
        ([$findings[] | select(.tag == "must-fix")] | length) as $must
        | ([$findings[] | select(.tag == "suggestion")] | length) as $sugg
        | (if $mode == "inline" then [$findings[] | select(has("path") | not)] else $findings end) as $in_body
        | {query: $mutation, variables: {input: {
            pullRequestId: $state.id, commitOID: $state.headSha, event: "COMMENT",
            body: ("\($round_marker) \($state.round + 1) of \($state.max): \($must) must-fix, \($sugg) suggestion\n\n" + $summary
                   + (if ($in_body | length) > 0 then "\n\nFindings:\n" + ($in_body | map(listed) | join("\n")) else "" end)),
            threads: (if $mode == "inline" then [$findings[] | select(has("path")) | {path, line, side: "RIGHT", body: "[\(.tag)] \(.body)"}] else [] end)}}}'
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -ge 1 ] && [ $# -le 2 ] || usage_error
dry_run=""
if [ $# -eq 2 ]; then
    [ "$2" = "$DRY_RUN_FLAG" ] || usage_error
    dry_run=1
fi
require_issue_numbers "$1"

input=$(cat)
jq -e 'type == "object" and (.findings | type == "array")
    and all(.findings[]; (.tag | IN("must-fix", "suggestion")) and (.body | type == "string" and length > 0)
        and ((has("path") and has("line")) or ((has("path") | not) and (has("line") | not)))
        and (if has("line") then (.line | type == "number" and . >= 1 and . == floor) else true end))' <<<"$input" >/dev/null 2>&1 ||
    die "the findings must be JSON like the usage shows: every finding has a tag (must-fix or suggestion), a body, and path and line together"
findings=$(jq -c .findings <<<"$input")
summary=$(jq -r '.summary // ""' <<<"$input")

resolve_repo
state=$(load_pr_state "$1")
[ "$(jq -r .pr <<<"$state")" != "null" ] || die "no open pull request closes issue #$1"
if [ "$(jq -r .capped <<<"$state")" = "true" ]; then
    die "round cap reached ($MAX_REVIEW_ROUNDS rounds): do not post another review, escalate the open items to the user"
fi

request=$(build_request inline)
[ -n "$request" ] || die "could not build the review request"
if [ -n "$dry_run" ]; then
    jq 'del(.query)' <<<"$request"
    exit 0
fi

counts=$(jq -r '"must-fix=\([.[] | select(.tag == "must-fix")] | length) suggestion=\([.[] | select(.tag == "suggestion")] | length) inline=\([.[] | select(has("path"))] | length)"' <<<"$findings")
note=""
if ! out=$(printf '%s' "$request" | gh api graphql --input - 2>&1); then
    if [ "$(jq '.variables.input.threads | length' <<<"$request")" -gt 0 ] && grep -q -i -E "$INLINE_REJECTED_PATTERN" <<<"$out"; then
        request=$(build_request body)
        out=$(printf '%s' "$request" | gh api graphql --input - 2>&1) || die "GitHub API call failed: $(api_error "$out")"
        note=" (inline comments were rejected by GitHub: all findings are in the review body)"
        counts=${counts%inline=*}inline=0
    else
        die "GitHub API call failed: $(api_error "$out")"
    fi
fi
echo "posted: round $(($(jq -r .round <<<"$state") + 1)) of $MAX_REVIEW_ROUNDS $counts url=$(jq -r '.data.addPullRequestReview.pullRequestReview.url' <<<"$out")$note"
