#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_pr-feedback.sh - tests for pr-feedback.sh (stubbed gh, no network).
# usage: test_pr-feedback.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${PR_FEEDBACK_UNDER_TEST:-$SCRIPT_DIR/pr-feedback.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

TAG='<!-- abk:review-items-handled -->'
STUB_DIR="$TEST_TMP/stub"
mkdir -p "$STUB_DIR" "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
args="$*"
printf '%s\n----\n' "$args" >> "$STUB_DIR/queries.log"
if [[ "$args" == *"pullRequests("* ]]; then cat "$STUB_DIR/prs.json"; exit 0; fi
if [[ "$args" == *"pullRequest(number"* ]]; then cat "$STUB_DIR/details.json"; exit 0; fi
echo "stub gh: unexpected call: $args" >&2
exit 99
STUB
chmod +x "$TEST_TMP/bin/gh"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH"

# Write the stub data: one open PR (number 9) that closes issue 4 and one that closes issue 8.
write_data() {
    echo '{"data":{"repository":{"pullRequests":{"nodes":[
        {"number":3,"url":"https://x/3","headRefName":"F/8/x","closingIssuesReferences":{"nodes":[{"number":8}]}},
        {"number":9,"url":"https://x/9","headRefName":"F/4/x","closingIssuesReferences":{"nodes":[{"number":4}]}}]}}}}' > "$STUB_DIR/prs.json"
    jq -n --arg tag "$TAG" '{data: {repository: {pullRequest: {
        reviewThreads: {nodes: [
            {isResolved: false, path: "a.sh", line: 12, comments: {nodes: [{author: {login: "rev"}, body: "still open"}]}},
            {isResolved: true, path: "b.sh", line: 1, comments: {nodes: [{author: {login: "rev"}, body: "resolved"}]}}]},
        comments: {nodes: [
            {author: {login: "rev"}, body: "old comment, already handled", createdAt: "2026-11-22T10:00:00Z"},
            {author: {login: "me"}, body: "Review items handled:\n- old comment: fixed in abc\n\n\($tag)", createdAt: "2026-11-22T11:00:00Z"},
            {author: {login: "rev"}, body: "new comment after the summary", createdAt: "2026-11-22T12:00:00Z"},
            {author: {login: "rev"}, body: "Review items handled: a human typed this, no tag", createdAt: "2026-11-22T12:30:00Z"}]},
        reviews: {nodes: [
            {state: "CHANGES_REQUESTED", body: "superseded review", createdAt: "2026-11-22T09:00:00Z", author: {login: "rev"}},
            {state: "APPROVED", body: "", createdAt: "2026-11-22T13:00:00Z", author: {login: "rev"}},
            {state: "COMMENTED", body: "", createdAt: "2026-11-22T13:30:00Z", author: {login: "rev"}}]}}}}}' > "$STUB_DIR/details.json"
}

# Run the whole suite with the current shell.
run_suite() {
    write_data
    run_script 4
    check_that "the PR that closes the issue is found" [ "$(jq -r .pr <<<"$OUT")" = "9" ]
    check_that "its branch and url are reported" [ "$(jq -r '"\(.branch) \(.url)"' <<<"$OUT")" = "F/4/x https://x/9" ]
    check_that "the time of the coder's summary (found by its tag) is reported" [ "$(jq -r .handledAt <<<"$OUT")" = "2026-11-22T11:00:00Z" ]
    check_that "only unresolved threads are listed" [ "$(jq -c '[.threads[].comments[].body]' <<<"$OUT")" = '["still open"]' ]
    check_that "comments before the summary and the summary itself are not listed" [ "$(jq -c '[.comments[].body] | map(select(. == "old comment, already handled" or startswith("Review items handled:\n- old")))' <<<"$OUT")" = "[]" ]
    check_that "a comment after the summary is listed" [ "$(jq -r '[.comments[].body] | any(. == "new comment after the summary")' <<<"$OUT")" = "true" ]
    check_that "a human comment that only starts like the marker is just feedback, not the summary" [ "$(jq -r '[.comments[].body] | any(startswith("Review items handled: a human typed"))' <<<"$OUT")" = "true" ]
    check_that "a review before the summary is not listed" [ "$(jq -r '[.reviews[].body] | any(. == "superseded review")' <<<"$OUT")" = "false" ]
    check_that "an empty COMMENTED review is not listed" [ "$(jq -c '[.reviews[].state]' <<<"$OUT")" = '["APPROVED"]' ]
    check_that "the PR lookup asks for the most recently updated PRs first" grep -q "UPDATED_AT" "$STUB_DIR/queries.log"

    run_script 8
    check_that "another issue gets its own PR" [ "$(jq -r .pr <<<"$OUT")" = "3" ]
    run_script 77
    check_that "an issue without an open PR gives pr null" [ "$OUT" = '{"pr": null}' ]
    run_script abc
    check_that "a non-number is refused" [ "$RC" -ne 0 ]
    run_script
    check_that "no argument is a usage error" [ "$RC" -ne 0 ]
}

for_each_shell run_suite
finish
