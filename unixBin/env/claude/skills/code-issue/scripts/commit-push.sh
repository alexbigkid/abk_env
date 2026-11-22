#!/usr/bin/env bash

#------------------------------------------------------------------------------
# commit-push.sh - sign a commit with the coder key and push the feature branch.
#
# Needs: git, gpg, gh (for the HTTPS credentials). Config, set once (see GIT-SETUP.md):
#   git config --global coder.signingkey <fingerprint>
#   git config --global coder.name  "ABK Coder Agent"
#   git config --global coder.email <verified email of the GitHub account that holds the key>
# Optional: CODER_GH_TOKEN (token of a separate GitHub account) is used for the push.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # lib.sh belongs to the project-board skill, https-env.sh is next to this script
source "$(dirname "$0")/../../project-board/scripts/lib.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/https-env.sh"

BRANCH_PATTERN='^[BDFRT]/[0-9]+/[A-Za-z0-9._-]+$'
GOOD_SIGNATURES="GU"

usage() {
    cat <<USAGE
usage: commit-push.sh "<commit message>" (--all | <file>...)
Stages the given files (or all changes), makes ONE commit signed with the coder key and pushes
the current branch over HTTPS. Refuses to run on any branch that is not {Type}/{n}/{name}
(Type is one of B D F R T), when the coder config is missing, when nothing is staged, and
when the signature of the new commit is not good. Never force-pushes. Setup: GIT-SETUP.md
USAGE
}

# Print a git config value of the coder, or fail with the setup hint.
coder_config() {
    git config --get "coder.$1" || die "git config coder.$1 is not set. Set up the coder identity first (skills/code-issue/GIT-SETUP.md); the coder never commits unsigned."
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac
[ $# -ge 2 ] || usage_error
message=$1
shift

branch=$(git branch --show-current)
[[ "$branch" =~ $BRANCH_PATTERN ]] || die "refusing to commit on '$branch': the coder only commits on {Type}/{n}/{name} branches"
signing_key=$(coder_config signingkey)
coder_name=$(coder_config name)
coder_email=$(coder_config email)
gpg --list-secret-keys "$signing_key" >/dev/null 2>&1 || die "the coder signing key $signing_key is not in the gpg keyring"

if [ "$1" = "--all" ]; then git add -A; else git add -- "$@"; fi
if git diff --cached --quiet; then die "nothing staged to commit"; fi

signing=(-c "user.name=$coder_name" -c "user.email=$coder_email" -c "user.signingkey=$signing_key" -c gpg.program=gpg -c gpg.format=openpgp -c commit.gpgsign=true)
git "${signing[@]}" commit -S -m "$message" >/dev/null
signature=$(git "${signing[@]}" log -1 "--format=%G?")
case "$GOOD_SIGNATURES" in *"$signature"*) ;; *) die "the new commit is not signed with a good signature (status '$signature'); not pushing" ;; esac

git push --set-upstream origin "$branch" >/dev/null 2>&1 ||
    die "push of '$branch' failed (rejected or no access); the commit $(git rev-parse --short HEAD) is local. Report it, do not force-push."
echo "pushed: $branch $(git rev-parse --short HEAD) signature=$signature signed-as=\"$coder_name <$coder_email>\""
