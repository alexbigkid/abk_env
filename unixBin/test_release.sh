#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_release.sh - tests for .github/scripts/release.sh (the release job of the pipeline).
#
# Self-contained: a stub gh logs its calls, nothing touches GitHub. Runs once per shell found.
#
# usage: test_release.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_UNDER_TEST=$SCRIPT_DIR/../.github/scripts/release.sh

# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/env/claude/skills/project-board/scripts/testing-lib.sh"
handle_test_help "$@"

export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" user.name "Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "test@example.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

# Stub gh: logs every call to $GH_LOG, answers the reads of release.sh; GH_STUB_MAIN_SHA is the sha of main.
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
# GH_STUB_FAIL: a call that starts with this text fails
if [ -n "${GH_STUB_FAIL:-}" ] && [[ "$*" == "$GH_STUB_FAIL"* ]]; then exit 1; fi
case "$*" in
    "api repos/o/r/git/ref/heads/main"*) echo "${GH_STUB_MAIN_SHA:-abc123}" ;;
    "api repos/o/r/contents/VERSION?ref=main"*) echo "blobsha" ;;
    "pr create"*) echo "https://github.com/o/r/pull/7" ;;
    "pr view"*) echo "mergesha" ;;
esac
exit 0
STUB
chmod +x "$TEST_TMP/bin/gh"
export PATH="$TEST_TMP/bin:$PATH"

export GH_LOG="$TEST_TMP/gh.log"
export GH_REPO=o/r
export GITHUB_SHA=abc123

# New case: a git repo with VERSION 1.2.3 and an empty gh log.
new_case() {
    CASE_DIR=$(mktemp -d "$TEST_TMP/case.XXXXXX")
    cd "$CASE_DIR" || exit 1
    git init -q
    echo "1.2.3" > VERSION
    git add VERSION && git commit -q -m "first"
    : > "$GH_LOG"
    unset GH_STUB_MAIN_SHA GH_STUB_FAIL
}

# Run the script with a tag and a result; sets OUT and RC.
run_release() {
    GITHUB_REF_NAME=$1 run_script "$2"
}

run_suite() {
    new_case
    run_release rel-minor pass
    check_that "pass: succeeds" [ "$RC" -eq 0 ]
    check_that "pass: branch release/v1.3.0 created" grep -q "git/refs -f ref=refs/heads/release/v1.3.0" "$GH_LOG"
    check_that "pass: VERSION committed on the branch" grep -q "PUT repos/o/r/contents/VERSION.*branch=release/v1.3.0" "$GH_LOG"
    check_that "pass: pull request opened" grep -q "pr create --base main --head release/v1.3.0 --title Release v1.3.0" "$GH_LOG"
    check_that "pass: squash merge" grep -q "pr merge https://github.com/o/r/pull/7 --squash" "$GH_LOG"
    check_that "pass: tag v1.3.0 on the merge commit" grep -q "ref=refs/tags/v1.3.0 -f sha=mergesha" "$GH_LOG"
    check_that "pass: rel tag deleted" grep -q "DELETE repos/o/r/git/refs/tags/rel-minor" "$GH_LOG"
    check_that "pass: branch deleted" grep -q "DELETE repos/o/r/git/refs/heads/release/v1.3.0" "$GH_LOG"

    new_case
    run_release rel-patch fail
    check_that "fail: exits non-zero" [ "$RC" -ne 0 ]
    check_that "fail: says no release" grep -q "no release" <<< "$OUT"
    check_that "fail: rel tag deleted" grep -q "DELETE repos/o/r/git/refs/tags/rel-patch" "$GH_LOG"
    check_that "fail: nothing else" [ "$(wc -l < "$GH_LOG" | tr -d ' ')" = 1 ]

    new_case
    GH_STUB_MAIN_SHA=other run_release rel-patch pass
    check_that "main moved: fails" [ "$RC" -ne 0 ]
    check_that "main moved: rel tag deleted" grep -q "DELETE repos/o/r/git/refs/tags/rel-patch" "$GH_LOG"
    check_that "main moved: no branch created" [ -z "$(grep 'refs/heads/release' "$GH_LOG")" ]

    new_case
    GH_STUB_FAIL="pr create" run_release rel-patch pass
    check_that "pr create fails: fails" [ "$RC" -ne 0 ]
    check_that "pr create fails: branch deleted" grep -q "DELETE repos/o/r/git/refs/heads/release/v1.2.4" "$GH_LOG"
    check_that "pr create fails: rel tag deleted" grep -q "DELETE repos/o/r/git/refs/tags/rel-patch" "$GH_LOG"

    new_case
    GH_STUB_FAIL="pr merge" MERGE_TRIES=2 MERGE_WAIT=0 run_release rel-patch pass
    check_that "merge fails: fails" [ "$RC" -ne 0 ]
    check_that "merge fails: tried twice" [ "$(grep -c 'pr merge' "$GH_LOG" | tr -d ' ')" = 2 ]
    check_that "merge fails: branch deleted" grep -q "DELETE repos/o/r/git/refs/heads/release/v1.2.4" "$GH_LOG"
    check_that "merge fails: rel tag deleted" grep -q "DELETE repos/o/r/git/refs/tags/rel-patch" "$GH_LOG"

    new_case
    GH_STUB_FAIL="api repos/o/r/git/refs -f ref=refs/heads" run_release rel-patch pass
    check_that "branch creation fails: fails" [ "$RC" -ne 0 ]
    check_that "branch creation fails: rel tag deleted" grep -q "DELETE repos/o/r/git/refs/tags/rel-patch" "$GH_LOG"
    check_that "branch creation fails: branch not deleted" [ -z "$(grep 'DELETE.*refs/heads' "$GH_LOG")" ]

    new_case
    run_release rel-patch bogus
    check_that "bad result: usage error" [ "$RC" -ne 0 ]
}

for_each_shell run_suite
finish
