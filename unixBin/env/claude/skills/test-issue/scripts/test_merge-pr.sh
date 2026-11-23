#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_merge-pr.sh - tests for merge-pr.sh (stubbed gh, no network).
# usage: test_merge-pr.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${MERGE_PR_UNDER_TEST:-$SCRIPT_DIR/merge-pr.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill, the others to the review skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../review/scripts/review-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../review/scripts/review-stub-lib.sh"

STUB_DIR="$TEST_TMP/stub"
MERGE_SHA="1111111111111111111111111111111111111111"
mkdir -p "$TEST_TMP/bin" "$STUB_DIR"
export STUB_DIR GH_REPO="o/r" PATH="$TEST_TMP/bin:$PATH"

# Create the stub gh: the merge commit and the checks come from files, `gh pr merge` is recorded in merge.log.
# shellcheck disable=SC2016  # the text is a script for the stub, expanded when the stub runs
make_merge_gh_stub() {
    {
        cat <<'STUB'
#!/usr/bin/env bash
dir=${STUB_DIR:?}
args="$*"
if [ "$1 $2" = "pr merge" ]; then echo "$args" >> "$dir/merge.log"; [ -f "$dir/merge-refused" ] && { echo "gh: refused" >&2; exit 1; }; touch "$dir/merged"; exit 0; fi
if [[ "$args" == *"mergeCommit"* ]]; then cat "$dir/merge-commit.json"; exit 0; fi
if [[ "$args" == *"statusCheckRollup"* ]]; then cat "$dir/checks.json"; exit 0; fi
STUB
        printf '%s\n' "$GH_STUB_READS"
        printf '%s\n' 'echo "stub gh: unexpected call: $args" >&2' 'exit 99'
    } > "$TEST_TMP/bin/gh"
    chmod +x "$TEST_TMP/bin/gh"
}

# Set the checks of the PR: a JSON array of contexts (CheckRun or StatusContext nodes).
set_checks() {
    jq -n --argjson nodes "$1" '{data: {repository: {pullRequest: {title: "Add the thing", commits: {nodes: [{commit: {statusCheckRollup: {contexts: {nodes: $nodes}}}}]}}}}}' > "$STUB_DIR/checks.json"
}

# Set the state GitHub reports after the merge: MERGED or OPEN, and whether the merge commit is signed.
set_merge_commit() {
    jq -n --arg state "$1" --argjson valid "$2" --arg sha "$MERGE_SHA" \
        '{data: {repository: {pullRequest: {state: $state, mergeCommit: {oid: $sha, signature: {isValid: $valid}}}}}}' > "$STUB_DIR/merge-commit.json"
}

# Build a CheckRun node: name, status, conclusion, required.
run() { jq -n --arg n "$1" --arg s "$2" --arg c "$3" --argjson r "$4" '{__typename: "CheckRun", name: $n, status: $s, conclusion: (if $c == "" then null else $c end), isRequired: $r}'; }

# Reset the stub to a PR that can be merged: all checks green, MERGEABLE, merge commit signed.
reset() {
    rm -f "$STUB_DIR/merge.log" "$STUB_DIR/merged" "$STUB_DIR/merge-refused" "$STUB_DIR/queries.log"
    set_pr 0 no 0
    set_checks "[$(run build COMPLETED SUCCESS true)]"
    set_merge_commit MERGED true
}

# Run the whole suite with the current shell.
run_suite() {
    reset
    run_script 5 --commit "$HEAD_SHA"
    check_that "a green mergeable PR is merged" [ "$RC" -eq 0 ]
    check_that "the success line names the merge commit and that it is verified" [ "$OUT" = "merged: $MERGE_SHA verified=true" ]
    check_that "the merge is a squash merge pinned to the tested commit" grep -q -- "--squash --match-head-commit $HEAD_SHA" "$STUB_DIR/merge.log"
    check_that "the merge commit closes the issue" grep -q -- "--body Closes #5" "$STUB_DIR/merge.log"
    check_that "the merge title is the PR title with its number" grep -q -- "--subject Add the thing (#7)" "$STUB_DIR/merge.log"
    check_that "it never rebases" [ "$(grep -c -- "--rebase" "$STUB_DIR/merge.log")" = "0" ]

    reset
    run_script 5 --commit "$HEAD_SHA" --dry-run
    check_that "dry run succeeds" [ "$RC" -eq 0 ]
    check_that "dry run says what it would merge" grep -q "^would merge: PR #7" <<<"$OUT"
    check_that "dry run does not merge" [ ! -f "$STUB_DIR/merge.log" ]

    reset
    set_pr none no 0
    run_script 5 --commit "$HEAD_SHA"
    check_that "refuses without an open PR" [ "$RC" -eq 1 ]
    check_that "says why" grep -q "no open pull request" <<<"$OUT"

    reset
    run_script 5 --commit "0000000000000000000000000000000000000000"
    check_that "refuses when the PR head is not the tested commit" [ "$RC" -eq 1 ]
    check_that "says to test again" grep -q "test again" <<<"$OUT"
    check_that "nothing was merged for a moved head" [ ! -f "$STUB_DIR/merge.log" ]

    reset
    set_pr 0 no 0 CONFLICTING
    run_script 5 --commit "$HEAD_SHA"
    check_that "refuses a conflicting PR" [ "$RC" -eq 1 ]
    check_that "names the state" grep -q "CONFLICTING" <<<"$OUT"
    set_pr 0 no 0 UNKNOWN
    run_script 5 --commit "$HEAD_SHA"
    check_that "refuses a PR whose mergeable state is unknown" [ "$RC" -eq 1 ]

    reset
    set_checks "[$(run build COMPLETED SUCCESS true), $(run lint COMPLETED FAILURE true)]"
    run_script 5 --commit "$HEAD_SHA"
    check_that "a failed required check gives exit 2" [ "$RC" -eq 2 ]
    check_that "the failed check is named" grep -q "checks failed: lint" <<<"$OUT"
    check_that "nothing was merged with a failed check" [ ! -f "$STUB_DIR/merge.log" ]

    reset
    set_checks "[$(run build IN_PROGRESS "" true)]"
    run_script 5 --commit "$HEAD_SHA"
    check_that "a running required check gives exit 3" [ "$RC" -eq 3 ]
    check_that "the running check is named" grep -q "still running: build" <<<"$OUT"
    check_that "nothing was merged with a running check" [ ! -f "$STUB_DIR/merge.log" ]

    reset
    set_checks "[$(run build COMPLETED SUCCESS true), $(run optional COMPLETED FAILURE false), $(run slow IN_PROGRESS "" false)]"
    run_script 5 --commit "$HEAD_SHA"
    check_that "failed or running checks that are not required do not block when some are required" [ "$RC" -eq 0 ]

    reset
    set_checks "[$(run build COMPLETED SUCCESS false), $(run lint COMPLETED TIMED_OUT false)]"
    run_script 5 --commit "$HEAD_SHA"
    check_that "when no check is marked required every check gates the merge" [ "$RC" -eq 2 ]

    reset
    set_checks '[{"__typename":"StatusContext","context":"ci/legacy","state":"ERROR","isRequired":true}]'
    run_script 5 --commit "$HEAD_SHA"
    check_that "a failed commit status counts like a failed check run" [ "$RC" -eq 2 ]
    set_checks '[{"__typename":"StatusContext","context":"ci/legacy","state":"PENDING","isRequired":true}]'
    run_script 5 --commit "$HEAD_SHA"
    check_that "a pending commit status counts as running" [ "$RC" -eq 3 ]

    reset
    set_checks "[$(run build COMPLETED SKIPPED true), $(run docs COMPLETED NEUTRAL true)]"
    run_script 5 --commit "$HEAD_SHA"
    check_that "skipped and neutral checks do not block" [ "$RC" -eq 0 ]

    reset
    set_checks '[]'
    run_script 5 --commit "$HEAD_SHA"
    check_that "a PR without any check can be merged (nothing gates it)" [ "$RC" -eq 0 ]

    reset
    jq -n '{data: {repository: {pullRequest: {title: "t", commits: {nodes: [{commit: {statusCheckRollup: null}}]}}}}}' > "$STUB_DIR/checks.json"
    run_script 5 --commit "$HEAD_SHA"
    check_that "a commit without a check rollup can be merged" [ "$RC" -eq 0 ]

    reset
    set_merge_commit MERGED false
    run_script 5 --commit "$HEAD_SHA"
    check_that "a merge commit that is not verified gives exit 4" [ "$RC" -eq 4 ]
    check_that "the output says verified=false" grep -q "verified=false" <<<"$OUT"

    reset
    touch "$STUB_DIR/merge-refused"
    run_script 5 --commit "$HEAD_SHA"
    check_that "a refused merge is an error" [ "$RC" -eq 1 ]
    check_that "it says the merge was refused" grep -q "was refused" <<<"$OUT"

    reset
    set_merge_commit OPEN true
    run_script 5 --commit "$HEAD_SHA"
    check_that "a PR that GitHub does not report as merged is an error" [ "$RC" -eq 1 ]

    run_script
    check_that "no arguments is a usage error" [ "$RC" -eq 1 ]
    run_script 5 --commit abc
    check_that "a short sha is refused" [ "$RC" -eq 1 ]
    run_script x --commit "$HEAD_SHA"
    check_that "a non-numeric issue is refused" [ "$RC" -eq 1 ]
    run_script 5 --commit "$HEAD_SHA" --force
    check_that "an unknown option is refused" [ "$RC" -eq 1 ]
    run_script --help
    check_that "--help prints the usage and exits 0" [ "$RC" -eq 0 ]
}

make_merge_gh_stub
for_each_shell run_suite
finish
