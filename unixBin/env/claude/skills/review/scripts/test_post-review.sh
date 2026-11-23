#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_post-review.sh - tests for post-review.sh (stubbed gh, no network).
# usage: test_post-review.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${POST_REVIEW_UNDER_TEST:-$SCRIPT_DIR/post-review.sh}
# shellcheck disable=SC1091  # testing-lib.sh is next to this script
source "$SCRIPT_DIR/testing-lib.sh"

STUB_DIR="$TEST_TMP/stub"
make_gh_stub "$TEST_TMP/bin"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH"

DEFAULT_FINDINGS='{"summary":"## Standards\nok\n## Spec\nmissing a test","findings":[
  {"tag":"must-fix","body":"no test for the refusal","path":"scripts/a.sh","line":12},
  {"tag":"suggestion","body":"rename the helper"}]}'

# Run the script under test with the findings on stdin; sets OUT and RC.
post() {
    OUT=$(printf '%s' "$FINDINGS" | "$RUNNER" "$SCRIPT_UNDER_TEST" "$@" 2>&1)
    RC=$?
}

# Print the number of requests the stub has recorded.
requests() { find "$STUB_DIR/requests" -type f | wc -l | tr -d ' '; }

# Run the whole suite with the current shell.
run_suite() {
    FINDINGS=$DEFAULT_FINDINGS
    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0

    post 5 --dry-run
    check_that "dry-run prints the request and posts nothing" [ "$RC" -eq 0 ] && [ "$(requests)" = "0" ]
    check_that "dry-run: the review is a plain comment on the head commit of the PR" [ "$(jq -r '.variables.input | "\(.event) \(.pullRequestId) \(.commitOID)"' <<<"$OUT")" = "COMMENT PR_node abc123" ]
    check_that "dry-run: the title counts the round and the findings" [ "$(jq -r '.variables.input.body | split("\n")[0]' <<<"$OUT")" = "Review round 3 of 10: 1 must-fix, 1 suggestion" ]
    check_that "dry-run: only the located finding becomes an inline thread, with its tag" [ "$(jq -c '.variables.input.threads' <<<"$OUT")" = '[{"path":"scripts/a.sh","line":12,"side":"RIGHT","body":"[must-fix] no test for the refusal"}]' ]
    check_that "dry-run: the finding without a location is listed in the body" [ "$(jq -r '.variables.input.body | contains("- [suggestion] rename the helper")' <<<"$OUT")" = "true" ]
    check_that "dry-run: the summary is in the body" [ "$(jq -r '.variables.input.body | contains("missing a test")' <<<"$OUT")" = "true" ]

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    post 5
    check_that "posting works and reports round, counts and url" [ "$OUT" = "posted: round 3 of 10 must-fix=1 suggestion=1 inline=1 url=https://example.invalid/pr/7#review-1" ]
    check_that "exactly one request was sent" [ "$(requests)" = "1" ]

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    echo reject-inline-once > "$STUB_DIR/post-mode"
    post 5
    check_that "an inline comment rejected by GitHub is retried with everything in the body" [ "$RC" -eq 0 ] && [ "$(requests)" = "2" ]
    check_that "the retry has no threads and lists the located finding with its place" [ "$(jq -c '.variables.input.threads | length' "$STUB_DIR/requests/2.json")" = "0" ] && [ "$(jq -r '.variables.input.body | contains("`scripts/a.sh:12` no test for the refusal")' "$STUB_DIR/requests/2.json")" = "true" ]
    check_that "the output says so" [ "$(grep -c 'inline comments were rejected' <<<"$OUT")" = "1" ] && [ "$(grep -c 'inline=0' <<<"$OUT")" = "1" ]

    make_gh_stub "$TEST_TMP/bin"
    set_pr 2 no 0
    echo reject-always > "$STUB_DIR/post-mode"
    post 5
    check_that "any other API failure is an error with GitHub's reason, and is not retried" [ "$RC" -ne 0 ] && [ "$(requests)" = "1" ] && grep -q "Something else broke" <<<"$OUT"

    make_gh_stub "$TEST_TMP/bin"
    set_pr 10 no 0
    post 5
    check_that "after 10 rounds it refuses, tells to escalate and posts nothing" [ "$RC" -ne 0 ] && [ "$(requests)" = "0" ] && grep -q "escalate" <<<"$OUT"
    set_pr 9 no 0
    post 5 --dry-run
    check_that "round 10 is still allowed" [ "$(jq -r '.variables.input.body | split("\n")[0] | startswith("Review round 10 of 10")' <<<"$OUT")" = "true" ]

    set_pr none no 0
    post 5
    check_that "no open PR for the issue is refused" [ "$RC" -ne 0 ] && grep -q "no open pull request" <<<"$OUT"

    set_pr 0 no 0
    FINDINGS='not json'; post 5
    check_that "invalid JSON is refused" [ "$RC" -ne 0 ] && [ "$(requests)" = "0" ]
    FINDINGS='{"findings":[{"tag":"nice-to-have","body":"x"}]}'; post 5
    check_that "an unknown tag is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"findings":[{"tag":"must-fix","body":""}]}'; post 5
    check_that "an empty body is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"findings":[{"tag":"must-fix","body":"x","path":"a.sh"}]}'; post 5
    check_that "a path without a line is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"findings":[{"tag":"must-fix","body":"x","path":"a.sh","line":0}]}'; post 5
    check_that "line 0 is refused" [ "$RC" -ne 0 ]
    FINDINGS='{"summary":"all good","findings":[]}'; post 5 --dry-run
    check_that "a clean review without findings is allowed" [ "$(jq -r '.variables.input.body | split("\n")[0]' <<<"$OUT")" = "Review round 1 of 10: 0 must-fix, 0 suggestion" ]
    post 5 --bogus
    check_that "an unknown option is a usage error" [ "$RC" -ne 0 ]
    FINDINGS=$(jq -nc '{summary: "s", findings: [{tag: "must-fix", body: "quote \" and \\ backslash and unicode ä", path: "a b/ä.sh", line: 3}]}')
    post 5 --dry-run
    check_that "spaces and unicode in the path survive" [ "$(jq -r '.variables.input.threads[0].path' <<<"$OUT")" = "a b/ä.sh" ]
    check_that "quotes, backslashes and unicode in the text survive" [ "$(jq -r '.variables.input.threads[0].body' <<<"$OUT")" = '[must-fix] quote " and \ backslash and unicode ä' ]
}

for_each_shell run_suite
finish
