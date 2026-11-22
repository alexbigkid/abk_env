#!/usr/bin/env bash

#------------------------------------------------------------------------------
# commit-push.sh - sign a commit with the coder key and push the feature branch.
#
# Needs: git, gpg, gh (for the HTTPS credentials). Config, set once per user (GIT-SETUP.md):
#   git config --global coder.signingkey <fingerprint>
#   git config --global coder.name  "ABK Coder Agent"
#   git config --global coder.email <verified email of your GitHub account>
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill, https-env.sh is next to this script
source "$(dirname "$0")/../../project-board/scripts/lib.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/https-env.sh"

BRANCH_PATTERN='^[BDFRT]/[0-9]+/[A-Za-z0-9._-]+$'
GOOD_SIGNATURE_PATTERN="^[GU]$"
PUSH_ERROR_PATTERN="rejected|error:|fatal:|denied|failed|Permission"
SECRET_PATTERN='(^|/)(\.env(\.[^/]+)?|id_(rsa|ed25519|ecdsa|dsa)[^/]*|[^/]*\.(pem|key|p12|pfx))$'
SECRET_EXCEPTIONS='\.(example|sample|template|dist)$'
ALL_FLAG="--all"

usage() {
    cat <<USAGE
usage: commit-push.sh "<commit message>" ($ALL_FLAG | <file>...)
Stages the given files (or all changes, untracked files included), makes ONE commit signed with
the coder key and pushes the current branch over HTTPS. It refuses, and leaves nothing pushed:
  - any branch that is not {Type}/{n}/{name} (Type is one of B D F R T)
  - missing coder config, or a signing key that is not in the gpg keyring
  - an index that already has staged changes (they would end up in the commit)
  - nothing to commit, or staged files that look like secrets (.env, *.pem, *.key, id_rsa ...)
  - any commit not yet on the remote whose signature is not good
It never force-pushes. Setup: GIT-SETUP.md
USAGE
}

# Print a git config value of the coder, or fail with the setup hint.
coder_config() {
    git config --get "coder.$1" || die "git config coder.$1 is not set. Set up the coder identity first (skills/code-issue/GIT-SETUP.md); the coder never commits unsigned."
}

# Succeed when the given git signature status (%G?) counts as a good signature.
is_good_signature() { [[ "$1" =~ $GOOD_SIGNATURE_PATTERN ]]; }

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -ge 2 ] || usage_error
message=$1
shift
stage_all=""
if [ "$1" = "$ALL_FLAG" ]; then
    [ $# -eq 1 ] || die "$ALL_FLAG cannot be combined with file names"
    stage_all=1
fi

branch=$(git branch --show-current)
[[ "$branch" =~ $BRANCH_PATTERN ]] || die "refusing to commit on '$branch': the coder only commits on {Type}/{n}/{name} branches"
signing_key=$(coder_config signingkey)
coder_name=$(coder_config name)
coder_email=$(coder_config email)
gpg --list-secret-keys "$signing_key" >/dev/null 2>&1 || die "the coder signing key $signing_key is not in the gpg keyring"
git diff --cached --quiet || die "the index already has staged changes; unstage them (git reset) or commit them yourself first, the coder only commits what it stages itself"

if [ -n "$stage_all" ]; then git add -A; else git add -- "$@"; fi
if git diff --cached --quiet; then die "nothing staged to commit"; fi
secret_hits=$(git diff --cached --name-only | grep -E -i "$SECRET_PATTERN" | grep -v -E -i "$SECRET_EXCEPTIONS" || true)
if [ -n "$secret_hits" ]; then
    git reset -q
    die "refusing to commit files that look like secrets (unstaged again): $(tr '\n' ' ' <<<"$secret_hits")"
fi

signing=(-c "user.name=$coder_name" -c "user.email=$coder_email" -c "user.signingkey=$signing_key" -c gpg.program=gpg -c gpg.format=openpgp -c commit.gpgsign=true)
git "${signing[@]}" commit -S -m "$message" >/dev/null

# Every commit that is not on the remote yet must be signed well, not only the new one.
base_ref=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo "origin/main")
range="HEAD~1..HEAD"
if git rev-parse --verify -q "$base_ref" >/dev/null; then range="$base_ref..HEAD"; fi
unsigned=""
while read -r sha signature; do
    if ! is_good_signature "$signature"; then unsigned+=" $(git rev-parse --short "$sha")($signature)"; fi
done < <(git "${signing[@]}" log "--format=%H %G?" "$range")
[ -z "$unsigned" ] || die "not pushing: commit(s) without a good signature:$unsigned. They stay local; report it."

checked=$(git log --format=%H "$range" | wc -l | tr -d ' ')
if ! push_out=$(git push --set-upstream origin "$branch" 2>&1); then
    reason=$(grep -E "$PUSH_ERROR_PATTERN" <<<"$push_out" | head -n 3 | tr '\n' ' ' || true)
    [ -n "$reason" ] || reason=$(tail -n 3 <<<"$push_out" | tr '\n' ' ')
    die "push of '$branch' failed: $reason. The commit $(git rev-parse --short HEAD) stays local; report it, do not force-push."
fi
echo "pushed: $branch $(git rev-parse --short HEAD) signed-as=\"$coder_name <$coder_email>\" commits-checked=$checked"
