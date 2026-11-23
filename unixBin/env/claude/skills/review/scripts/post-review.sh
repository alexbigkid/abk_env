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
ROUND_FLAG="--round"
COMMIT_FLAG="--commit"
INLINE_REJECTED_PATTERN="(line|path|thread)[^.]*(diff|resolve|invalid|exist)"
FINDING_MARK_MUST_FIX="@must-fix"
FINDING_MARK_SUGGESTION="@suggestion"

# Print the findings given as text (see the usage) as the JSON the rest of the script works with.
text_to_json() {
    jq -Rs --arg must "$FINDING_MARK_MUST_FIX" --arg sugg "$FINDING_MARK_SUGGESTION" '
        def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
        split("\n")
        | reduce .[] as $line ({summary: [], findings: []};
            if ($line | startswith($must) or startswith($sugg)) then
                ($line | capture("^(?<mark>\\S+)(?: +(?<loc>\\S+))? *$")) as $m
                | .findings += [{tag: ($m.mark | ltrimstr("@")), loc: $m.loc, body: []}]
            elif (.findings | length) == 0 then .summary += [$line]
            else .findings[-1].body += [$line] end)
        | {summary: (.summary | join("\n") | trim),
           findings: [.findings[] | {tag, body: (.body | join("\n") | trim)}
                      + (if .loc == null then {} elif (.loc | test("^.+:[0-9]+$") | not) then error("the location of a finding must be <file>:<line>") else {path: (.loc | sub(":[0-9]+$"; "")), line: (.loc | capture(":(?<n>[0-9]+)$").n | tonumber)} end)]}'
}

# shellcheck disable=SC2016  # $input is a GraphQL variable, not shell
MUTATION='mutation($input: AddPullRequestReviewInput!){addPullRequestReview(input:$input){pullRequestReview{id url}}}'

usage() {
    cat <<USAGE
usage: post-review.sh <issue-number> $ROUND_FLAG <k> $COMMIT_FLAG <sha> [$DRY_RUN_FLAG]      (the findings come on stdin)
Findings as TEXT (use this one in a heredoc: a headless permission check refuses a heredoc with JSON in it):
  <markdown summary of the review: all lines before the first finding>
  $FINDING_MARK_MUST_FIX <file>:<line>        a finding with a location, its text on the following lines
  <text, any number of lines>
  $FINDING_MARK_SUGGESTION                      a finding without a location
  <text>
Findings as JSON (when the shell is not restricted; a first character "{" selects it):
{"summary": "<markdown summary of the review>",
 "findings": [{"tag": "must-fix" | "suggestion", "body": "<text>", "path": "<file>", "line": <n>}, ...]}
"path" and "line" go together: "line" is the line number in the NEW version of the file and must lie
inside the diff. A finding without them is listed in the review body. Every comment starts with its tag.
$ROUND_FLAG is the round you read with review-state.sh and $COMMIT_FLAG the commit you reviewed (the HEAD of
your worktree, at least 7 hex digits). The review is refused when another review was posted meanwhile
(round changed) or the PR got new commits (head moved): start over from reading the state.
It is posted as a plain comment review (GitHub does not allow requesting changes on a pull request of
your own account), titled "$ROUND_MARKER <k> of $MAX_REVIEW_ROUNDS". Refuses when no open pull request closes the issue or
when $MAX_REVIEW_ROUNDS rounds are used up (park the issue for the user instead, PR-MODE.md step 6). If GitHub rejects an
inline comment (a line outside the diff) and no review was posted, the review is posted once more with
all findings in its body. $DRY_RUN_FLAG prints the request only.
USAGE
}

# shellcheck disable=SC2153  # ROUND_TAG comes from review-lib.sh
# Build the GraphQL request: mode "inline" puts located findings into threads, mode "body" lists all in the body.
build_request() {
    jq -nc --argjson state "$state" --argjson findings "$findings" --arg summary "$summary" --arg mode "$1" \
        --arg round_marker "$ROUND_MARKER" --arg round_tag "$ROUND_TAG" --arg mutation "$MUTATION" '
        def listed: "- [\(.tag)] " + (if has("path") then "`\(.path):\(.line)` " else "" end) + .body;
        ([$findings[] | select(.tag == "must-fix")] | length) as $must
        | ([$findings[] | select(.tag == "suggestion")] | length) as $sugg
        | (if $mode == "inline" then [$findings[] | select(has("path") | not)] else $findings end) as $in_body
        | {query: $mutation, variables: {input: {
            pullRequestId: $state.id, commitOID: $state.headSha, event: "COMMENT",
            body: ("\($round_marker) \($state.round + 1) of \($state.max): \($must) must-fix, \($sugg) suggestion\n\n" + $summary
                   + (if ($in_body | length) > 0 then "\n\nFindings:\n" + ($in_body | map(listed) | join("\n")) else "" end)
                   + "\n\n" + $round_tag),
            threads: (if $mode == "inline" then [$findings[] | select(has("path")) | {path, line, side: "RIGHT", body: "[\(.tag)] \(.body)"}] else [] end)}}}'
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -ge 1 ] || usage_error
require_issue_numbers "$1"
issue=$1
shift
dry_run=""
round_pin=""
commit_pin=""
while [ $# -gt 0 ]; do
    case "$1" in
        "$DRY_RUN_FLAG") dry_run=1; shift ;;
        "$ROUND_FLAG") [ $# -ge 2 ] || usage_error; round_pin=$2; shift 2 ;;
        "$COMMIT_FLAG") [ $# -ge 2 ] || usage_error; commit_pin=$2; shift 2 ;;
        *) usage_error ;;
    esac
done
[ -n "$round_pin" ] && [ -n "$commit_pin" ] || usage_error
[[ "$round_pin" =~ ^[0-9]+$ ]] || die "$ROUND_FLAG needs the round number from review-state.sh"
[[ "$commit_pin" =~ ^[0-9a-f]{7,40}$ ]] || die "$COMMIT_FLAG needs the commit you reviewed (7 to 40 lower-case hex digits)"

input=$(cat)
case "$input" in
    "{"*) ;;
    *) input=$(text_to_json <<<"$input") || die "the findings text is malformed: a finding line is $FINDING_MARK_MUST_FIX <file>:<line> or $FINDING_MARK_SUGGESTION" ;;
esac
if ! check_error=$(jq -e 'type == "object" and (.findings | type == "array")
    and all(.findings[]; (.tag | IN("must-fix", "suggestion")) and (.body | type == "string" and length > 0)
        and ((has("path") and has("line")) or ((has("path") | not) and (has("line") | not)))
        and (if has("line") then (.line | type == "number" and . >= 1 and . == floor) else true end))' <<<"$input" 2>&1 >/dev/null); then
    die "the findings must be JSON like the usage shows: every finding has a tag (must-fix or suggestion), a body, and path and line together${check_error:+ ($check_error)}"
fi
findings=$(jq -c .findings <<<"$input")
summary=$(jq -r '.summary // ""' <<<"$input")

resolve_repo
state=$(load_pr_state "$issue")
[ "$(jq -r .pr <<<"$state")" != "null" ] || die "no open pull request closes issue #$issue"
if [ "$(jq -r .capped <<<"$state")" = "true" ]; then
    die "round cap reached ($MAX_REVIEW_ROUNDS rounds): do not post another review, park the issue for the user (PR-MODE.md step 6)"
fi
[ "$(jq -r .round <<<"$state")" = "$round_pin" ] ||
    die "the review state changed while you reviewed: the PR is at round $(jq -r .round <<<"$state"), you read round $round_pin; start over from reading the state"
head_sha=$(jq -r .headSha <<<"$state")
case "$head_sha" in
    "$commit_pin"*) ;;
    *) die "the PR head moved: it is $head_sha now, you reviewed $commit_pin; fetch it and review again" ;;
esac

request=$(build_request inline) || die "could not build the review request"
if [ -n "$dry_run" ]; then
    jq 'del(.query)' <<<"$request"
    exit 0
fi

counts=$(jq -r '"must-fix=\([.[] | select(.tag == "must-fix")] | length) suggestion=\([.[] | select(.tag == "suggestion")] | length) inline=\([.[] | select(has("path"))] | length)"' <<<"$findings")
note=""
if ! out=$(printf '%s' "$request" | gh api graphql --input - 2>&1); then
    if [ "$(jq '.variables.input.threads | length' <<<"$request")" -gt 0 ] && grep -q -i -E "$INLINE_REJECTED_PATTERN" <<<"$out"; then
        fresh=$(load_pr_state "$issue")
        [ "$(jq -r .round <<<"$fresh")" = "$(jq -r .round <<<"$state")" ] ||
            die "GitHub reported an error, but a review was posted meanwhile (the PR is at round $(jq -r .round <<<"$fresh") now); check the PR, not retrying: $(api_error "$out")"
        request=$(build_request body) || die "could not build the review request"
        out=$(printf '%s' "$request" | gh api graphql --input - 2>&1) || die "GitHub API call failed: $(api_error "$out")"
        note=" (inline comments were rejected by GitHub: all findings are in the review body)"
        counts=${counts%inline=*}inline=0
    else
        die "GitHub API call failed: $(api_error "$out")"
    fi
fi
echo "posted: round $(($(jq -r .round <<<"$state") + 1)) of $MAX_REVIEW_ROUNDS $counts url=$(jq -r '.data.addPullRequestReview.pullRequestReview.url' <<<"$out")$note"
