#!/usr/bin/env bash

#------------------------------------------------------------------------------
# test_commit-push.sh - tests for commit-push.sh.
#
# Self-contained: a throwaway GPG key, its own git config (GIT_CONFIG_GLOBAL) and local bare
# repos as remotes. It never touches your keyring, your git config or GitHub. The whole suite
# runs once per shell found (/bin/bash, bash, zsh), because the script must work in all of them.
#
# usage: test_commit-push.sh        (exit code 0 = all passed)
#------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_UNDER_TEST=${COMMIT_PUSH_UNDER_TEST:-$SCRIPT_DIR/commit-push.sh}
BRANCH="F/4/test"
CODER_NAME="ABK Coder Agent"
CASE_NO=0

# shellcheck disable=SC1091  # testing-lib.sh belongs to the project-board skill
source "$SCRIPT_DIR/../../project-board/scripts/testing-lib.sh"
handle_test_help "$@"

for tool in git gpg; do
    command -v "$tool" >/dev/null || { echo "ERROR: $tool is required" >&2; exit 1; }
done

#---------------------------
# environment: temp dir, throwaway key, own git config
#---------------------------
# Stop the throwaway gpg-agent (the harness then removes the temp dir).
stop_gpg_agent() { GNUPGHOME="$TEST_TMP/g" gpgconf --kill gpg-agent 2>/dev/null; }
# shellcheck disable=SC2034  # used by cleanup in testing-lib.sh
TEST_CLEANUP_HOOK=stop_gpg_agent

export GNUPGHOME="$TEST_TMP/g"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "$CODER_NAME <coder-test@example.invalid>" ed25519 sign never >/dev/null 2>&1 ||
    { echo "ERROR: cannot create the throwaway gpg key" >&2; exit 1; }
KEY=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
git config --file "$GIT_CONFIG_GLOBAL" coder.signingkey "$KEY"
git config --file "$GIT_CONFIG_GLOBAL" coder.name "$CODER_NAME"
git config --file "$GIT_CONFIG_GLOBAL" coder.email "coder-test@example.invalid"

#---------------------------
# helpers
#---------------------------

# Run the script under test in the current repo with the current shell; sets OUT and RC.
run_cp() {
    OUT=$("$RUNNER" "$SCRIPT_UNDER_TEST" "$@" 2>&1)
    RC=$?
}

# Check that the script pushes: name, then its arguments.
expect_pushed() {
    local name=$1
    shift
    run_cp "$@"
    [ "$RC" -eq 0 ] && grep -q '^pushed:' <<<"$OUT"
    check "$name" $?
}

# Check that the script refuses with a message matching a pattern: name, pattern, then its arguments.
expect_refused() {
    local name=$1 pattern=$2
    shift 2
    run_cp "$@"
    [ "$RC" -ne 0 ] && grep -q "$pattern" <<<"$OUT"
    check "$name" $?
}

# Print the short sha of the test branch on the remote, or "none".
remote_sha() { git --git-dir="$REMOTE_DIR" rev-parse --short "$BRANCH" 2>/dev/null || echo "none"; }

# Succeed when a commit message matching the pattern is in the history of the current branch.
branch_has_commit() { git log --format=%s | grep -q "$1"; }

# Create a fresh bare remote and a clone on the test branch; the base commit is unsigned, by someone else.
# With --unpushed the base commit stays local, so the remote has no refs at all.
new_repo() {
    CASE_NO=$((CASE_NO + 1))
    CASE_DIR="$TEST_TMP/case-$CASE_NO"
    REMOTE_DIR="$CASE_DIR/remote.git"
    WORK="$CASE_DIR/work"
    mkdir -p "$CASE_DIR"
    git init -q --bare "$REMOTE_DIR"
    git --git-dir="$REMOTE_DIR" symbolic-ref HEAD refs/heads/main
    git clone -q "$REMOTE_DIR" "$WORK" 2>/dev/null
    cd "$WORK" || exit 1
    git config user.name "Someone Else"
    git config user.email "else@example.invalid"
    git config commit.gpgsign false
    echo base > base.txt
    git add base.txt
    git commit -q -m base
    git branch -M main
    if [ "${1:-}" != "--unpushed" ]; then git push -q origin main; fi
    git checkout -q -b "$BRANCH"
}

# Make a second clone of the remote, as another person, and print its path.
other_clone() {
    local dir="$CASE_DIR/other"
    git clone -q "$REMOTE_DIR" "$dir" 2>/dev/null
    git -C "$dir" config user.name o
    git -C "$dir" config user.email o@example.invalid
    git -C "$dir" config commit.gpgsign false
    echo "$dir"
}

# Commit as someone else, unsigned, on the current branch (not pushed): a commit the coder must refuse to push.
others_unsigned_commit() {
    echo "$1" > "$1.txt"
    git add "$1.txt"
    git -c commit.gpgsign=false commit -q -m "$1 (unsigned)"
}

#---------------------------
# the suite
#---------------------------
run_suite() {

    new_repo
    echo a > a.txt
    expect_pushed "signed commit is pushed" "add a" a.txt
    check_that "the remote has the commit" [ "$(remote_sha)" = "$(git rev-parse --short HEAD)" ]
    check_that "good signature, author and committer are the coder" [ "$(git -c gpg.program=gpg log -1 --format='%G?|%an|%cn')" = "G|$CODER_NAME|$CODER_NAME" ]

    new_repo
    git checkout -q main
    echo x > x.txt
    expect_refused "refuses main" "only commits on" "m" --all
    git checkout -q -b random-branch
    expect_refused "refuses a branch that is not {Type}/{n}/{name}" "only commits on" "m" --all

    new_repo
    echo x > x.txt
    git config --file "$GIT_CONFIG_GLOBAL" --unset coder.signingkey
    expect_refused "refuses without coder.signingkey (never unsigned)" "coder.signingkey is not set" "m" --all
    git config --file "$GIT_CONFIG_GLOBAL" coder.signingkey "$KEY"

    new_repo
    expect_refused "refuses when there is nothing to commit" "nothing staged" "m" base.txt
    echo pre > pre.txt
    git add pre.txt
    echo other > other.txt
    expect_refused "refuses an index that is already staged" "already has staged changes" "m" other.txt
    git reset -q

    new_repo
    for name in ".env" ".env.production" "ä.pem" "a b.pem" "id_rsa" "server.key"; do
        echo secret > "$name"
        expect_refused "refuses secret-looking file '$name'" "look like secrets" "m" --all
        check_that "'$name' is unstaged again" [ -z "$(git diff --cached --name-only)" ]
        rm -f "$name"
    done
    echo example > .env.example
    expect_pushed ".env.example is allowed" "example" --all

    new_repo
    echo K=1 > .env
    git add .env
    git -c commit.gpgsign=false commit -q -m "tracked .env (unsigned)"
    git push -q origin "$BRANCH"
    rm .env
    expect_pushed "deleting a tracked .env is allowed" "remove .env" .env
    echo k > a.txt
    git add a.txt
    git -c commit.gpgsign=false commit -q -m "a (unsigned)"
    git push -q origin "$BRANCH"
    mv a.txt a-key.pem
    expect_refused "renaming to a secret-like name is refused" "look like secrets" "m" --all

    new_repo
    echo x > x.txt
    expect_refused "--all cannot be combined with files" "cannot be combined" "m" --all x.txt
    run_cp "m"
    check_that "no files is a usage error" [ "$RC" -ne 0 ]

    new_repo
    before=$(remote_sha)
    others_unsigned_commit local-unsigned
    echo d > d.txt
    expect_refused "refuses when an earlier local commit is unsigned" "without a good signature" "m" d.txt
    check_that "nothing was pushed in that case" [ "$(remote_sha)" = "$before" ]

    new_repo
    other=$(other_clone)
    (cd "$other" && echo m > m.txt && git add m.txt && git commit -q -m "others main commit (unsigned)" && git push -q origin main)
    git fetch -q origin
    git -c user.name=c -c user.email=c@example.invalid -c user.signingkey="$KEY" -c gpg.program=gpg -c commit.gpgsign=true merge -q -S -m "merge main" origin/main >/dev/null 2>&1
    check_that "(setup) main's unsigned commit of the other author is in the branch" branch_has_commit "others main commit"
    echo c > c.txt
    expect_pushed "after merging main (others' unsigned commits) the push is allowed" "after merge" c.txt

    new_repo
    printf '#!/bin/sh\necho hook says no >&2\nexit 1\n' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo e > e.txt
    expect_refused "a failing commit is reported" "commit failed" "m" e.txt
    check_that "a failing commit leaves nothing staged" [ -z "$(git diff --cached --name-only)" ]
    rm .git/hooks/pre-commit
    expect_pushed "the next run works" "after hook" e.txt

    new_repo
    other=$(other_clone)
    (cd "$other" && git checkout -q -b "$BRANCH" && echo o > o.txt && git add o.txt && git commit -q -m other && git push -q origin "$BRANCH")
    echo f > f.txt
    expect_refused "a rejected push shows git's reason" "rejected" "m" f.txt

    new_repo
    echo base-of-test > r.txt
    git add r.txt
    git -c commit.gpgsign=false commit -q -m "base of test"
    git push -q origin "$BRANCH"
    echo first > first.txt
    expect_pushed "signed commit on a pushed branch" "first" first.txt
    good=$(git rev-parse HEAD)
    other=$(other_clone)
    (cd "$other" && git checkout -q "$BRANCH" && echo x > x.txt && git add x.txt && git commit -q -m "others unsigned" && git push -q origin "$BRANCH")
    git fetch -q origin
    git merge -q --ff-only "origin/$BRANCH"
    (cd "$other" && git push -q --force origin "$good:refs/heads/$BRANCH")
    echo s > s.txt
    expect_refused "a stale origin ref cannot hide an unsigned commit (fetch first)" "without a good signature" "m" s.txt

    new_repo
    git remote set-url origin "$CASE_DIR/does-not-exist.git"
    echo g > g.txt
    expect_refused "refuses when the remote cannot be fetched" "cannot fetch" "m" g.txt

    new_repo
    git remote remove origin
    echo h > h.txt
    expect_refused "refuses when there is no remote named origin" "cannot fetch" "m" h.txt

    new_repo --unpushed
    echo n > n.txt
    expect_refused "without any remote ref the whole history is checked" "without a good signature" "m" n.txt
    check_that "nothing was pushed to the empty remote" [ "$(remote_sha)" = "none" ]
}

for_each_shell run_suite
finish
