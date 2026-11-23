#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_gitRelease.sh - tests for gitRelease.sh.
#
# Self-contained: local bare repo as origin, a stub gh on PATH, no GPG key (the
# script reads its commit flags from GIT_RELEASE_COMMIT_FLAGS). Never touches
# GitHub or your git config. Runs once per shell found.
#
# usage: test_gitRelease.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_UNDER_TEST=$SCRIPT_DIR/gitRelease.sh
CASE_NO=0
STUB_URL="https://github.com/o/r/pull/99"

# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/env/claude/skills/project-board/scripts/testing-lib.sh"
handle_test_help "$@"

export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" user.name "Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "test@example.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export GIT_RELEASE_COMMIT_FLAGS="--no-gpg-sign"

# Stub gh: logs the calls; "pr list" answers the number of open release PRs (STUB_OPEN), "pr create" the URL.
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "\$STUB_LOG"
case "\$1 \$2" in
    "pr list") echo "\${STUB_OPEN:-0}" ;;
    "pr create") echo "$STUB_URL" ;;
esac
STUB
chmod +x "$TEST_TMP/bin/gh"
export PATH="$TEST_TMP/bin:$PATH"

# New case: origin + clone on main with VERSION 1.2.3, one tag and one commit after the tag.
new_repo() {
    CASE_NO=$((CASE_NO + 1))
    CASE_DIR=$TEST_TMP/case$CASE_NO
    export STUB_LOG=$CASE_DIR/gh.log
    export STUB_OPEN=0
    mkdir -p "$CASE_DIR"
    git init -q --bare "$CASE_DIR/origin.git"
    git clone -q "$CASE_DIR/origin.git" "$CASE_DIR/work" 2>/dev/null
    cd "$CASE_DIR/work" || exit 1
    git checkout -q -b main
    echo "1.2.3" > VERSION
    git add VERSION && git commit -q -m "first"
    git tag v1.2.3
    echo a > a.txt && git add a.txt && git commit -q -m "Add a thing (#7)"
    git push -q -u origin main 2>/dev/null
    : > "$STUB_LOG"
}

# Run the script in the current repo; sets OUT and RC.
run_rel() {
    OUT=$("$RUNNER" "$SCRIPT_UNDER_TEST" "$@" 2>&1)
    RC=$?
}

# Check that the script refused: name, expected text of the message, then its arguments.
expect_refused() {
    local name=$1 text=$2
    shift 2
    run_rel "$@"
    check_that "$name: refused" [ "$RC" -ne 0 ]
    check_that "$name: message" grep -q "$text" <<< "$OUT"
    check_that "$name: no pr created" [ "$(grep -c "pr create" "$STUB_LOG")" = 0 ]
    check_that "$name: no release branch pushed" [ -z "$(git ls-remote --heads origin 'release/*')" ]
}

# Check one release type: type, expected next version.
expect_version() {
    local type=$1 next=$2
    new_repo
    run_rel "$type"
    check_that "$type: succeeds" [ "$RC" -eq 0 ]
    check_that "$type: prints the url" grep -q "$STUB_URL" <<< "$OUT"
    check_that "$type: branch release/v$next on origin" [ -n "$(git ls-remote --heads origin "release/v$next")" ]
    check_that "$type: VERSION on the branch" [ "$(git --git-dir="$CASE_DIR/origin.git" show "release/v$next:VERSION")" = "$next" ]
    check_that "$type: commit message" [ "$(git --git-dir="$CASE_DIR/origin.git" log -1 --format=%s "release/v$next")" = "Release v$next" ]
    check_that "$type: back on main" [ "$(git branch --show-current)" = "main" ]
    check_that "$type: pr title" grep -q "pr create .*--title Release v$next" "$STUB_LOG"
    check_that "$type: pr body lists merged work" grep -q "Add a thing (#7)" "$STUB_LOG"
    check_that "$type: no auto-merge by default" [ "$(grep -c "pr merge" "$STUB_LOG")" = 0 ]
}

run_suite() {
    expect_version patch 1.2.4
    expect_version minor 1.3.0
    expect_version major 2.0.0

    new_repo
    run_rel patch --auto-merge
    check_that "auto-merge asks for squash" grep -q "pr merge .*--auto --squash" "$STUB_LOG"

    new_repo
    echo dirty > a.txt
    expect_refused "dirty tree" "not clean" patch

    new_repo
    echo new > untracked.txt
    expect_refused "untracked file" "not clean" patch

    new_repo
    git checkout -q -b other
    expect_refused "not on main" "main" patch

    new_repo
    git reset -q --hard HEAD~1
    expect_refused "main behind origin" "up to date" patch

    new_repo
    echo b > b.txt && git add b.txt && git commit -q -m "local only"
    expect_refused "main ahead of origin" "up to date" patch

    new_repo
    STUB_OPEN=1
    expect_refused "open release pr" "open" patch

    new_repo
    expect_refused "unknown type" "usage" bogus

    new_repo
    expect_refused "no type" "usage"
}

for_each_shell run_suite
finish
