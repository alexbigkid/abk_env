#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_cleanup-merged.sh - tests for cleanup-merged.sh (local bare repos as remotes, stubbed gh; no network).
# usage: test_cleanup-merged.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034  # used by run_script in testing-lib.sh
SCRIPT_UNDER_TEST=${CLEANUP_UNDER_TEST:-$SCRIPT_DIR/cleanup-merged.sh}
# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

STUB_DIR="$TEST_TMP/stub"
SC="$TEST_TMP/sc"
BRANCH="F/32/cleanup"
mkdir -p "$STUB_DIR/bin"
: > "$STUB_DIR/https-env.sh"
printf '%s\n' "[user]" "    name = Test" "    email = t@example.com" "[commit]" "    gpgsign = false" "[init]" "    defaultBranch = main" "[protocol \"file\"]" "    allow = always" > "$STUB_DIR/gitconfig"

# The stub gh: the default branch, the pull requests of the issue (file prs) and the pull request data (file pr-<n>.json).
# shellcheck disable=SC2016  # the text is a script for the stub, expanded when it runs
printf '%s\n' '#!/usr/bin/env bash' 'dir=${STUB_DIR:?}' 'args="$*"' \
    'case "$args" in' \
    '  "repo view"*) echo main ;;' \
    '  "issue view"*) cat "$dir/prs" ;;' \
    '  "pr view"*) cat "$dir/pr-$3.json" ;;' \
    '  *) echo "stub gh: unexpected call: $args" >&2; exit 99 ;;' \
    'esac' > "$STUB_DIR/bin/gh"
chmod +x "$STUB_DIR/bin/gh"
export STUB_DIR GIT_CONFIG_GLOBAL="$STUB_DIR/gitconfig" GIT_CONFIG_NOSYSTEM=1 HTTPS_ENV_SCRIPT="$STUB_DIR/https-env.sh" PATH="$STUB_DIR/bin:$PATH"

# Make a commit with a file in the repo of the given dir.
commit_in() { ( cd "$1" && echo "$2" > "$2.txt" && git add "$2.txt" && git commit -qm "$2" ); }

# Build the scenario: origin.git, the checkout "work" on the feature branch (pushed), other branches with their own work,
# and a squash merge on main made by another clone. Sets HEAD_OID and MERGE_OID and writes the pull request #5 as merged.
make_scenario() {
    rm -rf "$SC"; mkdir -p "$SC"
    git init -q --bare "$SC/origin.git"
    git clone -q "$SC/origin.git" "$SC/work" 2>/dev/null
    commit_in "$SC/work" base
    ( cd "$SC/work" && git push -q origin main 2>/dev/null )
    ( cd "$SC/work" && git switch -q -c other-local && cd . ) && commit_in "$SC/work" unrelated-local
    ( cd "$SC/work" && git switch -q -c other-remote ) && commit_in "$SC/work" unrelated-remote
    ( cd "$SC/work" && git push -q origin other-remote 2>/dev/null && git switch -q main && git switch -q -c "$BRANCH" ) && commit_in "$SC/work" feature
    ( cd "$SC/work" && git push -q -u origin "$BRANCH" 2>/dev/null )
    HEAD_OID=$(git -C "$SC/work" rev-parse HEAD)
    git clone -q "$SC/origin.git" "$SC/merger" 2>/dev/null
    commit_in "$SC/merger" squashed
    ( cd "$SC/merger" && git push -q origin main 2>/dev/null )
    MERGE_OID=$(git -C "$SC/merger" rev-parse HEAD)
    write_pr 5 MERGED "$BRANCH" "$HEAD_OID" "$MERGE_OID" main false
    echo 5 > "$STUB_DIR/prs"
}

# Write the data of a pull request: number, state, branch, head commit, merge commit, base branch, fork flag.
write_pr() {
    jq -nc --argjson n "$1" --arg s "$2" --arg b "$3" --arg h "$4" --arg m "$5" --arg base "$6" --argjson f "$7" \
        '{number: $n, state: $s, headRefName: $b, headRefOid: $h, baseRefName: $base, isCrossRepository: $f, mergeCommit: (if $m == "" then null else {oid: $m} end)}' > "$STUB_DIR/pr-$1.json"
}

# Run the script in the checkout for issue 32.
run_cleanup() { cd "$SC/work" && run_script 32; }

# True when the local / remote branch exists.
has_local() { git -C "$SC/work" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }
has_remote() { git -C "$SC/origin.git" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }
current_branch() { git -C "$SC/work" branch --show-current; }

# Check that nothing was changed: branches, remote and checkout as before.
nothing_touched() { has_local "$BRANCH" && has_remote "$BRANCH" && [ "$(current_branch)" = "$BRANCH" ]; }

# Check that the other branches are untouched.
others_untouched() { has_local other-local && has_remote other-remote && has_local other-remote && has_local main; }

run_suite() {
    make_scenario
    run_cleanup
    check_that "merged and clean: exit 0" [ "$RC" -eq 0 ]
    check_that "switched to main" [ "$(current_branch)" = "main" ]
    check_that "main is pulled (the merge commit is in it)" git -C "$SC/work" merge-base --is-ancestor "$MERGE_OID" HEAD
    check_that "local merged branch deleted" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/work" "$BRANCH"
    check_that "remote merged branch deleted" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/origin.git" "$BRANCH"
    check_that "its tracking reference is gone" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/remotes/origin/$2" >/dev/null' _ "$SC/work" "$BRANCH"
    check_that "every other branch is left alone (including the one with unrelated work)" others_untouched
    check_that "the tracking reference of another branch is left alone" git -C "$SC/work" rev-parse --verify --quiet refs/remotes/origin/other-remote
    check_that "the report says what was deleted" grep -q "deleted remote branch $BRANCH" <<<"$OUT"

    make_scenario
    echo dirty >> "$SC/work/feature.txt"
    run_cleanup
    check_that "dirty tree: exit 0" [ "$RC" -eq 0 ]
    check_that "dirty tree: not switched" [ "$(current_branch)" = "$BRANCH" ]
    check_that "dirty tree: the local branch is kept (checked out)" has_local "$BRANCH"
    check_that "dirty tree: it says why" grep -q "not clean" <<<"$OUT"
    check_that "dirty tree: the change is still there" grep -q dirty "$SC/work/feature.txt"
    check_that "dirty tree: the remote branch is still cleaned (its tip is the merged head)" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/origin.git" "$BRANCH"

    make_scenario
    git -C "$SC/work" switch -q other-local
    run_cleanup
    check_that "other branch checked out: exit 0" [ "$RC" -eq 0 ]
    check_that "other branch checked out: not switched" [ "$(current_branch)" = "other-local" ]
    check_that "other branch checked out: it says so" grep -q "not the merged branch" <<<"$OUT"
    check_that "other branch checked out: the merged branch is deleted locally" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/work" "$BRANCH"
    check_that "other branch checked out: and remotely" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/origin.git" "$BRANCH"
    check_that "other branch checked out: main is not pulled" bash -c '! git -C "$1" merge-base --is-ancestor "$2" main' _ "$SC/work" "$MERGE_OID"

    make_scenario
    commit_in "$SC/work" extra
    run_cleanup
    check_that "extra local commit: exit 0" [ "$RC" -eq 0 ]
    check_that "extra local commit: the local branch is kept" has_local "$BRANCH"
    check_that "extra local commit: it says so" grep -q "kept local branch" <<<"$OUT"
    check_that "extra local commit: the remote branch (still the merged head) is deleted" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/origin.git" "$BRANCH"
    check_that "extra local commit: the commit is not lost" git -C "$SC/work" log -1 --format=%s "$BRANCH" | grep -q extra

    make_scenario
    git clone -q "$SC/origin.git" "$SC/third" 2>/dev/null
    git -C "$SC/third" switch -q "$BRANCH"
    commit_in "$SC/third" later
    ( cd "$SC/third" && git push -q origin "$BRANCH" 2>/dev/null )
    run_cleanup
    check_that "moved remote branch: exit 0" [ "$RC" -eq 0 ]
    check_that "moved remote branch: the remote branch is kept" has_remote "$BRANCH"
    check_that "moved remote branch: it says so" grep -q "kept remote branch" <<<"$OUT"
    check_that "moved remote branch: the local branch (merged head) is deleted" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/work" "$BRANCH"

    make_scenario
    git -C "$SC/origin.git" update-ref -d "refs/heads/$BRANCH"
    run_cleanup
    check_that "remote branch already deleted: exit 0" [ "$RC" -eq 0 ]
    check_that "remote branch already deleted: counts as done" grep -q "already deleted" <<<"$OUT"
    check_that "remote branch already deleted: the local branch is deleted" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null' _ "$SC/work" "$BRANCH"
    check_that "remote branch already deleted: its stale tracking reference is gone" bash -c '! git -C "$1" rev-parse --verify --quiet "refs/remotes/origin/$2" >/dev/null' _ "$SC/work" "$BRANCH"

    make_scenario
    write_pr 5 OPEN "$BRANCH" "$HEAD_OID" "" main false
    run_cleanup
    check_that "not merged: exit 0" [ "$RC" -eq 0 ]
    check_that "not merged: nothing touched" nothing_touched
    check_that "not merged: other branches untouched" others_untouched
    check_that "not merged: it says so" grep -q "nothing touched" <<<"$OUT"

    make_scenario
    : > "$STUB_DIR/prs"
    run_cleanup
    check_that "no pull request: exit 0, nothing touched" nothing_touched

    make_scenario
    write_pr 5 MERGED "$BRANCH" "$HEAD_OID" "0000000000000000000000000000000000000001" main false
    run_cleanup
    check_that "merge commit not on main: exit 0" [ "$RC" -eq 0 ]
    check_that "merge commit not on main: nothing touched" nothing_touched
    check_that "merge commit not on main: it says so" grep -q "not on main" <<<"$OUT"

    make_scenario
    write_pr 5 MERGED "$BRANCH" "" "$MERGE_OID" main false
    run_cleanup
    check_that "no usable head commit: nothing touched" nothing_touched

    make_scenario
    write_pr 5 MERGED "$BRANCH" "$HEAD_OID" "$MERGE_OID" develop false
    run_cleanup
    check_that "merged into another base: nothing touched" nothing_touched

    make_scenario
    write_pr 5 MERGED main "$MERGE_OID" "$MERGE_OID" main false
    run_cleanup
    check_that "default branch as head: exit 0" [ "$RC" -eq 0 ]
    check_that "default branch as head: refused" grep -q "refused" <<<"$OUT"
    check_that "default branch as head: main still local and remote" bash -c 'git -C "$1" rev-parse --verify --quiet refs/heads/main >/dev/null && git -C "$2" rev-parse --verify --quiet refs/heads/main >/dev/null' _ "$SC/work" "$SC/origin.git"
    check_that "default branch as head: the checkout is not switched" nothing_touched

    make_scenario
    write_pr 5 MERGED "$BRANCH" "$HEAD_OID" "$MERGE_OID" main true
    run_cleanup
    check_that "fork branch: refused" grep -q "fork" <<<"$OUT"
    check_that "fork branch: nothing touched" nothing_touched

    make_scenario
    write_pr 4 OPEN "$BRANCH" "$HEAD_OID" "" main false
    printf '%s\n' 4 5 > "$STUB_DIR/prs"
    run_cleanup
    check_that "an open and a merged pull request: the merged one is used" grep -q "deleted remote branch" <<<"$OUT"

    run_script
    check_that "no issue number is a usage error" [ "$RC" -eq 1 ]
    run_script abc
    check_that "a non-number is a usage error" [ "$RC" -eq 1 ]
    run_script --help
    check_that "--help prints the usage and exits 0" [ "$RC" -eq 0 ]
}

for_each_shell run_suite
finish
