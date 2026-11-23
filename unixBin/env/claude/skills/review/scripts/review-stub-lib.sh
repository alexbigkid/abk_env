# shellcheck shell=bash
# shellcheck disable=SC2034  # used by the test scripts that source this file

#------------------------------------------------------------------------------
# review-stub-lib.sh - a stub `gh` and PR data for the tests of the review scripts.
# Sourced after the harness (project-board/scripts/testing-lib.sh) and review-lib.sh, not executed.
#------------------------------------------------------------------------------

HEAD_SHA="abcdef0123456789abcdef0123456789abcdef01"

# Create a stub `gh` in the given dir: the read queries come from files in STUB_DIR (GH_STUB_READS of the
# harness), posted reviews are recorded in STUB_DIR/requests. Post modes (STUB_DIR/post-mode): ok,
# reject-inline-once (a line outside the diff, then ok), reject-inline-but-posted (the same error, but a review
# was posted meanwhile), reject-timeline (an unrelated error that mentions "timeline"), reject-always.
# shellcheck disable=SC2016  # the text is a script for the stub, expanded when the stub runs
make_gh_stub() {
    mkdir -p "$1" "$STUB_DIR/requests"
    {
        cat <<'STUB'
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
            jq '.data.repository.pullRequest.reviews.nodes += [{body: "Review round 99\n\n<!-- abk:review-round -->", createdAt: "2026-11-23T23:00:00Z", author: {login: "o"}}]' "$dir/details.json" > "$dir/details.tmp" && mv "$dir/details.tmp" "$dir/details.json"
            echo "gh: Line must be part of the diff (HTTP 422)" >&2
            exit 1 ;;
        reject-timeline) echo "gh: The timeline service is unavailable (HTTP 422)" >&2; exit 1 ;;
        reject-always) echo "gh: Something else broke (HTTP 500)" >&2; exit 1 ;;
    esac
    exit 0
fi
STUB
        printf '%s\n' "$GH_STUB_READS"
        printf '%s\n' 'echo "stub gh: unexpected call: $args" >&2' 'exit 99'
    } > "$1/gh"
    chmod +x "$1/gh"
    echo '{"data":{"addPullRequestReview":{"pullRequestReview":{"id":"R1","url":"https://example.invalid/pr/7#review-1"}}}}' > "$STUB_DIR/post-ok.json"
    echo ok > "$STUB_DIR/post-mode"
    rm -f "$STUB_DIR"/requests/*.json "$STUB_DIR/queries.log" "$STUB_DIR/details.next"
}

# Describe the open PR of issue 5 for the stub: the number of review rounds already posted, the handled comment
# of the coder (no; new = after the last round; old = before the first round; edited = created before the first
# round but edited after the last one), how many review threads are unresolved, and the mergeable state (default
# MERGEABLE) and whether the last round review is on the current head commit (default false). Use "none" as first argument for no open PR at all. Besides the rounds, the PR has a human review
# and a human comment that start like the reviewer's title and the coder's marker but have no hidden tag.
set_pr() {
    if [ "$1" = "none" ]; then
        echo '{"data":{"repository":{"pullRequests":{"nodes":[]}}}}' > "$STUB_DIR/prs.json"
        return 0
    fi
    echo '{"data":{"repository":{"pullRequests":{"nodes":[
        {"number":99,"url":"https://x/99","headRefName":"F/9/other","baseRefName":"main","closingIssuesReferences":{"nodes":[{"number":9}]}},
        {"number":7,"url":"https://example.invalid/pr/7","headRefName":"F/5/test","baseRefName":"main","closingIssuesReferences":{"nodes":[{"number":5}]}}]}}}}' > "$STUB_DIR/prs.json"
    jq -n --argjson rounds "$1" --arg handled "$2" --argjson threads "$3" --arg mergeable "${4:-MERGEABLE}" --argjson reviewed_head "${5:-false}" --arg head "$HEAD_SHA" \
        --arg tag "$ROUND_TAG" --arg htag "$HANDLED_TAG" --argjson max "$MAX_REVIEW_ROUNDS" '
        def summary($created; $edited): {body: "Review items handled:\n- item: fixed in abc\n\n\($htag)", createdAt: $created, lastEditedAt: $edited};
        {data: {repository: {pullRequest: {id: "PR_node", headRefOid: $head, mergeable: $mergeable,
          reviews: {nodes: ([range(0; $rounds) | {body: "Review round \(. + 1) of \($max): 1 must-fix, 0 suggestion\n\n\($tag)", createdAt: "2026-11-23T1\(. % 10):00:00Z", commit: {oid: (if . == $rounds - 1 and $reviewed_head then $head else "0000000000000000000000000000000000000000" end)}}]
                            + [{body: "Review round 7 of \($max): a human wrote this title, no tag", createdAt: "2026-11-23T09:00:00Z"}])},
          comments: {nodes: ([{body: "an ordinary comment", createdAt: "2026-11-23T08:00:00Z", lastEditedAt: null},
                              {body: "Review items handled: a human typed this, no tag", createdAt: "2026-11-23T23:30:00Z", lastEditedAt: null}]
                             + (if $handled == "new" then [summary("2026-11-23T22:00:00Z"; null)] else [] end)
                             + (if $handled == "old" then [summary("2026-11-23T05:00:00Z"; null)] else [] end)
                             + (if $handled == "edited" then [summary("2026-11-23T05:00:00Z"; "2026-11-23T22:00:00Z")] else [] end))},
          reviewThreads: {nodes: ([range(0; $threads) | {isResolved: false}] + [{isResolved: true}])}}}}}
        | .data.repository.pullRequest |= (.reviews.nodes |= map(. + {author: {login: "o"}}) | .comments.nodes |= map(. + {author: {login: "o"}}))' > "$STUB_DIR/details.json"
}
