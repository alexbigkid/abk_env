# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the test scripts that source this file

#------------------------------------------------------------------------------
# testing-lib.sh - small test harness shared by the test_*.sh scripts of the review scripts.
# Sourced, not executed. Provides: check, check_that, run_script, for_each_shell, finish,
# a throwaway temp dir (TEST_TMP, removed on exit) and a stub `gh` (make_gh_stub).
#------------------------------------------------------------------------------

PASSED=0
FAILED=0
OUT=""
RC=0
RUNNER=""

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/rv-test.XXXXXX")

# Remove the temp dir (only a dir this harness created).
cleanup() {
    case "$TEST_TMP" in
        */rv-test.*) [ -d "$TEST_TMP" ] && rm -rf "$TEST_TMP" ;;
    esac
}
trap cleanup EXIT

# Record the result of one check: the name and the exit code of the test expression.
check() {
    if [ "$2" -eq 0 ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        echo "FAIL [$RUNNER] $1"
        echo "      output: $OUT"
    fi
}

# Check a condition given as a command (for example: check_that "name" [ -z "$x" ]).
check_that() {
    local name=$1
    shift
    "$@"
    check "$name" $?
}

# Run the script under test with the current shell and the given arguments; sets OUT and RC. Stdin passes through.
run_script() {
    OUT=$("$RUNNER" "$SCRIPT_UNDER_TEST" "$@" 2>&1)
    RC=$?
}

# Call the function given as argument once for every distinct shell found among /bin/bash, bash and zsh.
for_each_shell() {
    local candidate resolved seen duplicate seen_shells=()
    for candidate in /bin/bash bash zsh; do
        resolved=$(command -v "$candidate" 2>/dev/null) || continue
        duplicate=""
        for seen in ${seen_shells[@]+"${seen_shells[@]}"}; do
            if [ "$resolved" -ef "$seen" ]; then duplicate=1; fi
        done
        [ -z "$duplicate" ] || continue
        seen_shells+=("$resolved")
        RUNNER=$resolved
        echo "== running with: $RUNNER"
        "$1"
    done
}

# Print the summary and return the exit code of the test script.
finish() {
    echo "== $PASSED passed, $FAILED failed"
    [ "$FAILED" -eq 0 ]
}

# Create a stub `gh` in the given dir that answers the GraphQL calls of the review scripts from files in
# STUB_DIR (prs.json, details.json, post-ok.json, post-mode) and records each posted request in STUB_DIR/requests.
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
        reject-always) echo "gh: Something else broke (HTTP 500)" >&2; exit 1 ;;
    esac
    exit 0
fi
if [[ "$args" == *"pullRequests("* ]]; then cat "$dir/prs.json"; exit 0; fi
if [[ "$args" == *"pullRequest(number"* ]]; then cat "$dir/details.json"; exit 0; fi
echo "stub gh: unexpected call: $args" >&2
exit 99
STUB
    chmod +x "$1/gh"
    echo '{"data":{"addPullRequestReview":{"pullRequestReview":{"id":"R1","url":"https://example.invalid/pr/7#review-1"}}}}' > "$STUB_DIR/post-ok.json"
    echo ok > "$STUB_DIR/post-mode"
    rm -f "$STUB_DIR"/requests/*.json
}

# Describe the open PR of issue 5 for the stub: number of review rounds already posted, whether the coder
# wrote a handled comment (yes or no) and how many review threads are unresolved. Use "none" as first
# argument for no open PR at all.
set_pr() {
    if [ "$1" = "none" ]; then
        echo '{"data":{"repository":{"pullRequests":{"nodes":[]}}}}' > "$STUB_DIR/prs.json"
        return 0
    fi
    echo '{"data":{"repository":{"pullRequests":{"nodes":[
        {"number":99,"url":"https://x/99","headRefName":"F/9/other","baseRefName":"main","closingIssuesReferences":{"nodes":[{"number":9}]}},
        {"number":7,"url":"https://example.invalid/pr/7","headRefName":"F/5/test","baseRefName":"main","closingIssuesReferences":{"nodes":[{"number":5}]}}]}}}}' > "$STUB_DIR/prs.json"
    jq -n --argjson rounds "$1" --arg handled "$2" --argjson threads "$3" '
        {data: {repository: {pullRequest: {id: "PR_node", headRefOid: "abc123",
          reviews: {nodes: ([range(0; $rounds) | {body: "Review round \(. + 1) of 10: 1 must-fix, 0 suggestion", createdAt: "2026-11-23T1\(.):00:00Z"}]
                            + [{body: "a human review without the marker", createdAt: "2026-11-23T09:00:00Z"}])},
          comments: {nodes: ([{body: "an ordinary comment", createdAt: "2026-11-23T08:00:00Z"}]
                             + (if $handled == "yes" then [{body: "Review items handled:\n- item: fixed in abc", createdAt: "2026-11-23T20:00:00Z"}] else [] end))},
          reviewThreads: {nodes: ([range(0; $threads) | {isResolved: false}] + [{isResolved: true}])}}}}}' > "$STUB_DIR/details.json"
}
