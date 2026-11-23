#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_post-review.sh - tests for post-review.sh (stubbed gh, no network).
# usage: test_post-review.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${POST_REVIEW_UNDER_TEST:-$SCRIPT_DIR/post-review.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill, the others are next to this script
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/review-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/review-stub-lib.sh"

STUB_DIR="$TEST_TMP/stub"
make_gh_stub "$TEST_TMP/bin"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH"

DEFAULT_FINDINGS='{"summary":"## Standards\nok\n## Spec\nmissing a test","findings":[
  {"tag":"must-fix","body":"no test for the refusal","path":"scripts/a.sh","line":12},
  {"tag":"suggestion","body":"rename the helper"}]}'
FINDINGS=$DEFAULT_FINDINGS
SHORT_SHA=${HEAD_SHA:0:7}

# Run the script under test with the findings on stdin; sets OUT and RC. Arguments: issue, then the options.
post() {
    OUT=$(printf '%s' "$FINDINGS" | "$RUNNER" "$SCRIPT_UNDER_TEST" "$@" 2>&1)
    RC=$?
}

# Post for issue 5 with the pins of a PR at round $1 (default 2) and the current head; extra options follow.
post_pinned() {
    local round=${1:-2}
    shift || true
    post 5 --round "$round" --commit "$SHORT_SHA" "$@"
}

# Print the number of requests the stub has recorded.
requests() { find "$STUB_DIR/requests" -type f | wc -l | tr -d ' '; }

# Run the whole suite with the current shell.
run_suite() {
    FINDINGS=$DEFAULT_FINDINGS
    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0

    post_pinned 2 --dry-run
    check_that "dry-run succeeds" [ "$RC" -eq 0 ]
    check_that "dry-run posts nothing" [ "$(requests)" = "0" ]
    check_that "dry-run: the review is a plain comment on the head commit of the PR" [ "$(jq -r '.variables.input | "\(.event) \(.pullRequestId) \(.commitOID)"' <<<"$OUT")" = "COMMENT PR_node $HEAD_SHA" ]
    check_that "dry-run: the title counts the round and the findings" [ "$(jq -r '.variables.input.body | split("\n")[0]' <<<"$OUT")" = "$ROUND_MARKER 3 of $MAX_REVIEW_ROUNDS: 1 must-fix, 1 suggestion" ]
    check_that "dry-run: the body ends with the hidden tag the rounds are counted by" [ "$(jq -r '.variables.input.body | endswith("\n\n" + "<!-- abk:review-round -->")' <<<"$OUT")" = "true" ]
    check_that "dry-run: only the located finding becomes an inline thread, with its tag" [ "$(jq -c '.variables.input.threads' <<<"$OUT")" = '[{"path":"scripts/a.sh","line":12,"side":"RIGHT","body":"[must-fix] no test for the refusal"}]' ]
    check_that "dry-run: the finding without a location is listed in the body" [ "$(jq -r '.variables.input.body | contains("- [suggestion] rename the helper")' <<<"$OUT")" = "true" ]
    check_that "dry-run: the summary is in the body" [ "$(jq -r '.variables.input.body | contains("missing a test")' <<<"$OUT")" = "true" ]

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    post_pinned 2
    check_that "posting works and reports round, counts and url" [ "$OUT" = "posted: round 3 of $MAX_REVIEW_ROUNDS must-fix=1 suggestion=1 inline=1 url=https://example.invalid/pr/7#review-1" ]
    check_that "exactly one request was sent" [ "$(requests)" = "1" ]

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    post_pinned 1
    check_that "a review based on an older round is refused (someone posted meanwhile)" [ "$RC" -ne 0 ]
    check_that "that refusal says the state changed" grep -q "state changed" <<<"$OUT"
    check_that "that refusal posts nothing" [ "$(requests)" = "0" ]
    post 5 --round 2 --commit "1234567"
    check_that "a review of an older commit is refused (the PR head moved)" [ "$RC" -ne 0 ]
    check_that "that refusal says the head moved" grep -q "head moved" <<<"$OUT"
    check_that "that refusal posts nothing" [ "$(requests)" = "0" ]
    post 5 --round 2 --commit "$HEAD_SHA" --dry-run
    check_that "the full commit sha is accepted as well" [ "$RC" -eq 0 ]
    post 5 --round 2
    check_that "the commit pin is required" [ "$RC" -ne 0 ]
    post 5 --commit "$SHORT_SHA"
    check_that "the round pin is required" [ "$RC" -ne 0 ]
    post 5 --round two --commit "$SHORT_SHA"
    check_that "a round that is not a number is refused" [ "$RC" -ne 0 ]
    post 5 --round 2 --commit "xyz"
    check_that "a commit that is not hex is refused" [ "$RC" -ne 0 ]

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    echo reject-inline-once > "$STUB_DIR/post-mode"
    post_pinned 2
    check_that "an inline comment rejected by GitHub is retried and succeeds" [ "$RC" -eq 0 ]
    check_that "the retry was a second request" [ "$(requests)" = "2" ]
    check_that "the retry has no threads" [ "$(jq -c '.variables.input.threads | length' "$STUB_DIR/requests/2.json")" = "0" ]
    check_that "the retry lists the located finding with its place" [ "$(jq -r '.variables.input.body | contains("`scripts/a.sh:12` no test for the refusal")' "$STUB_DIR/requests/2.json")" = "true" ]
    check_that "the output says the inline comments were rejected" grep -q "inline comments were rejected" <<<"$OUT"
    check_that "the output says inline=0" grep -q "inline=0" <<<"$OUT"

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    echo reject-inline-but-posted > "$STUB_DIR/post-mode"
    post_pinned 2
    check_that "when a review was posted meanwhile there is no retry (no double posting)" [ "$RC" -ne 0 ]
    check_that "only the first request was sent" [ "$(requests)" = "1" ]
    check_that "the error says a review may be there already" grep -q "posted meanwhile" <<<"$OUT"

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    echo reject-timeline > "$STUB_DIR/post-mode"
    post_pinned 2
    check_that "an unrelated error that merely mentions 'timeline' is not retried" [ "$(requests)" = "1" ]
    check_that "it is reported with GitHub's reason" grep -q "timeline service" <<<"$OUT"
    echo reject-always > "$STUB_DIR/post-mode"
    rm -f "$STUB_DIR"/requests/*.json
    post_pinned 2
    check_that "any other API failure is an error" [ "$RC" -ne 0 ]
    check_that "it is not retried" [ "$(requests)" = "1" ]
    check_that "it carries GitHub's reason" grep -q "Something else broke" <<<"$OUT"

    make_gh_stub "$TEST_TMP/bin"
    set_pr "$MAX_REVIEW_ROUNDS" no 0
    post_pinned "$MAX_REVIEW_ROUNDS"
    check_that "at the cap it refuses" [ "$RC" -ne 0 ]
    check_that "at the cap it posts nothing" [ "$(requests)" = "0" ]
    check_that "at the cap it says to park the issue" grep -q "park the issue" <<<"$OUT"
    set_pr $((MAX_REVIEW_ROUNDS - 1)) no 0
    post_pinned $((MAX_REVIEW_ROUNDS - 1)) --dry-run
    check_that "the last round before the cap is still allowed" [ "$(jq -r '.variables.input.body | split("\n")[0] | startswith("'"$ROUND_MARKER $MAX_REVIEW_ROUNDS"' of")' <<<"$OUT")" = "true" ]

    set_pr none no 0
    post_pinned 0
    check_that "no open PR for the issue is refused" [ "$RC" -ne 0 ]
    check_that "the refusal says there is no open pull request" grep -q "no open pull request" <<<"$OUT"

    set_pr 0 no 0
    FINDINGS='not json'
    post_pinned 0
    check_that "invalid JSON is refused" [ "$RC" -ne 0 ]
    check_that "the reason of jq is shown" grep -q "parse error" <<<"$OUT"
    FINDINGS='{"findings":[{"tag":"nice-to-have","body":"x"}]}'
    post_pinned 0
    check_that "an unknown tag is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"findings":[{"tag":"must-fix","body":""}]}'
    post_pinned 0
    check_that "an empty body is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"findings":[{"tag":"must-fix","body":"x","path":"a.sh"}]}'
    post_pinned 0
    check_that "a path without a line is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"findings":[{"tag":"must-fix","body":"x","path":"a.sh","line":0}]}'
    post_pinned 0
    check_that "line 0 is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"summary":"all good","findings":[]}'
    post_pinned 0 --dry-run
    check_that "a clean review without findings is allowed" [ "$(jq -r '.variables.input.body | split("\n")[0]' <<<"$OUT")" = "$ROUND_MARKER 1 of $MAX_REVIEW_ROUNDS: 0 must-fix, 0 suggestion" ]
    post_pinned 0 --bogus
    check_that "an unknown option is a usage error" [ "$RC" -ne 0 ]
    FINDINGS=$(jq -nc '{summary: "s", findings: [{tag: "must-fix", body: "quote \" and \\ backslash and unicode ä", path: "a b/ä.sh", line: 3}]}')
    post_pinned 0 --dry-run
    check_that "spaces and unicode in the path survive" [ "$(jq -r '.variables.input.threads[0].path' <<<"$OUT")" = "a b/ä.sh" ]
    check_that "quotes, backslashes and unicode in the text survive" [ "$(jq -r '.variables.input.threads[0].body' <<<"$OUT")" = '[must-fix] quote " and \ backslash and unicode ä' ]
}

for_each_shell run_suite
finish
