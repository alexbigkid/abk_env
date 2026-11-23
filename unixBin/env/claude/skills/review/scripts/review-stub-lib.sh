# shellcheck shell=bash
# shellcheck disable=SC2034  # used by the test scripts that source this file

#------------------------------------------------------------------------------
# review-stub-lib.sh - a stub `gh` and PR data for the tests of the review scripts.
# Sourced after the harness (project-board/scripts/testing-lib.sh) and review-lib.sh, not executed.
#------------------------------------------------------------------------------

HEAD_SHA="abcdef0123456789abcdef0123456789abcdef01"

# Create a stub `gh` in the given dir that answers the GraphQL calls of the review scripts from files in
# STUB_DIR (prs.json, details.json, post-ok.json, post-mode) and records each posted request in STUB_DIR/requests
# and each query in STUB_DIR/queries.log. Post modes: ok, reject-inline-once (a line outside the diff, then ok),
# reject-inline-but-posted (the same error, but a review was posted meanwhile), reject-timeline (an unrelated
# error that mentions "timeline"), reject-always.
make_gh_stub() {
    mkdir -p "$1" "$STUB_DIR/requests"
    cat > "$1/gh" <<'STUB'
#!/usr/bin/env bash
dir=${STUB_DIR:?}
args="$*"
if [ "$1 $2" = "api graphql" ] && [[ "$args" == *"--input"* ]]; then
    n=$(find "$dir/requests" -type f | wc -l | tr -d ' ')
    cat > "$dir/requests/$((n + 1)).json"
    case "$(cat "$dir/post-mode")" in
        ok) cat "$dir/post-ok.json" ;;
        reject-inline-once)
            if [ "$n" -eq 0 ]; then echo "gh: Line must be part of the diff (HTTP 422)" >&2; exit 1; fi
            cat "$dir/post-ok.json" ;;
        reject-inline-but-posted)
            jq '.data.repository.pullRequest.reviews.nodes += [{body: "Review round 99\n\n<!-- abk:review-round -->", createdAt: "2026-11-23T23:00:00Z"}]' "$dir/details.json" > "$dir/details.tmp" && mv "$dir/details.tmp" "$dir/details.json"
            echo "gh: Line must be part of the diff (HTTP 422)" >&2
            exit 1 ;;
        reject-timeline) echo "gh: The timeline service is unavailable (HTTP 422)" >&2; exit 1 ;;
        reject-always) echo "gh: Something else broke (HTTP 500)" >&2; exit 1 ;;
    esac
    exit 0
fi
printf '%s\n----\n' "$args" >> "$dir/queries.log"
if [[ "$args" == *"pullRequests("* ]]; then cat "$dir/prs.json"; exit 0; fi
if [[ "$args" == *"pullRequest(number"* ]]; then cat "$dir/details.json"; exit 0; fi
echo "stub gh: unexpected call: $args" >&2
exit 99
STUB
    chmod +x "$1/gh"
    echo '{"data":{"addPullRequestReview":{"pullRequestReview":{"id":"R1","url":"https://example.invalid/pr/7#review-1"}}}}' > "$STUB_DIR/post-ok.json"
    echo ok > "$STUB_DIR/post-mode"
    rm -f "$STUB_DIR"/requests/*.json "$STUB_DIR/queries.log"
}

# Describe the open PR of issue 5 for the stub: the number of review rounds already posted, the handled comment
# of the coder (no, new = after the last round, old = before the first round), how many review threads are
# unresolved, and the mergeable state (default MERGEABLE). Use "none" as first argument for no open PR at all.
# Besides the rounds, the PR has a human review and a human comment that start like the reviewer's title and the coder's marker but have no hidden tag.
set_pr() {
    if [ "$1" = "none" ]; then
        echo '{"data":{"repository":{"pullRequests":{"nodes":[]}}}}' > "$STUB_DIR/prs.json"
        return 0
    fi
    echo '{"data":{"repository":{"pullRequests":{"nodes":[
        {"number":99,"url":"https://x/99","headRefName":"F/9/other","baseRefName":"main","closingIssuesReferences":{"nodes":[{"number":9}]}},
        {"number":7,"url":"https://example.invalid/pr/7","headRefName":"F/5/test","baseRefName":"main","closingIssuesReferences":{"nodes":[{"number":5}]}}]}}}}' > "$STUB_DIR/prs.json"
    jq -n --argjson rounds "$1" --arg handled "$2" --argjson threads "$3" --arg mergeable "${4:-MERGEABLE}" --arg head "$HEAD_SHA" --arg tag "$ROUND_TAG" --arg htag "$HANDLED_TAG" '
        {data: {repository: {pullRequest: {id: "PR_node", headRefOid: $head, mergeable: $mergeable,
          reviews: {nodes: ([range(0; $rounds) | {body: "Review round \(. + 1) of 10: 1 must-fix, 0 suggestion\n\n\($tag)", createdAt: "2026-11-23T1\(. % 10):00:00Z"}]
                            + [{body: "Review round 7 of 10: a human wrote this title, no tag", createdAt: "2026-11-23T09:00:00Z"}])},
          comments: {nodes: ([{body: "an ordinary comment", createdAt: "2026-11-23T08:00:00Z"}, {body: "Review items handled: a human typed this, no tag", createdAt: "2026-11-23T23:30:00Z"}]
                             + (if $handled == "new" then [{body: "Review items handled:\n- item: fixed in abc\n\n\($htag)", createdAt: "2026-11-23T22:00:00Z"}] else [] end)
                             + (if $handled == "old" then [{body: "Review items handled:\n- item: fixed in abc\n\n\($htag)", createdAt: "2026-11-23T05:00:00Z"}] else [] end))},
          reviewThreads: {nodes: ([range(0; $threads) | {isResolved: false}] + [{isResolved: true}])}}}}}' > "$STUB_DIR/details.json"
}
