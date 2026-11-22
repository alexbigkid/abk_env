# shellcheck shell=bash
# shellcheck disable=SC2034  # REPO, OWNER and REPO_NAME are used by the scripts that source this file

#------------------------------------------------------------------------------
# lib.sh - shared helpers of the project-board and prioritize scripts.
# Sourced by board.sh, blockers.sh and queue.sh, not executed.
#
# The scripts talk to GitHub through GraphQL only: one query that reads
# everything a command needs and at most one request with all the mutations.
# That keeps the number of API calls (and the rate limit usage) minimal.
#------------------------------------------------------------------------------

# Print the message and stop the script.
die() { echo "ERROR: $*" >&2; exit 1; }

# Print the usage (defined by the calling script) to stderr and stop the script.
usage_error() { usage >&2; exit 1; }

# Print only the message of a failed gh call (the text after its last "gh: ").
api_error() { local m=${1##*gh: }; echo "${m##*$'\n'}"; }

# Resolve REPO, OWNER and REPO_NAME without an API call (GH_REPO, else the git remote "origin").
resolve_repo() {
    local remote_url=${GH_REPO:-}
    if [ -z "$remote_url" ]; then
        remote_url=$(git remote get-url origin 2>/dev/null) || die "cannot determine the repository (set GH_REPO or add a git remote 'origin')"
    fi
    REPO=$(sed -E 's#^(git@|ssh://git@|https?://)[^/:]+[/:]##; s#\.git$##' <<<"$remote_url")
    [[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || die "cannot read owner/name from '$remote_url'"
    OWNER=${REPO%%/*}
    REPO_NAME=${REPO##*/}
}

# Run a GraphQL request with the given gh arguments and print the JSON answer; any API problem is an error.
gql() {
    local out
    local hint=""
    out=$(gh api graphql "$@" 2>&1) || {
        if grep -qi "scope" <<<"$out"; then hint=" (a missing scope can be added with: gh auth refresh -h github.com -s <scope>)"; fi
        die "GitHub API call failed: $(api_error "$out")$hint"
    }
    printf '%s\n' "$out"
}

# Print a string as a GraphQL string literal.
gql_string() { jq -rn --arg v "$1" '$v | @json'; }

# Fail unless all arguments are issue numbers.
require_issue_numbers() {
    local n
    for n in "$@"; do
        [[ "$n" =~ ^[0-9]+$ ]] || die "'$n' is not an issue number"
    done
}

# The mutations of one request (aliased m0, m1, ...) and the messages to print once it succeeded.
MUTATIONS=""
MUTATION_COUNT=0
MESSAGES=""

# Queue one mutation with the message to print on success.
queue_mutation() {
    MUTATIONS+=" m$MUTATION_COUNT: $1"
    MUTATION_COUNT=$((MUTATION_COUNT + 1))
    MESSAGES+="$2"$'\n'
}

# Send all queued mutations in one request and print their messages.
apply_mutations() {
    if [ "$MUTATION_COUNT" -gt 0 ]; then
        gql -f query="mutation{$MUTATIONS }" >/dev/null
    fi
    printf '%s' "$MESSAGES"
    MUTATIONS=""
    MUTATION_COUNT=0
    MESSAGES=""
}
