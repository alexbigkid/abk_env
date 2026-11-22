#!/usr/bin/env bash

#------------------------------------------------------------------------------
# with-https.sh - run a command (git, gh) with its git network operations over HTTPS.
#------------------------------------------------------------------------------
set -euo pipefail

# shellcheck disable=SC1091  # https-env.sh is next to this script
source "$(dirname "$0")/https-env.sh"

usage() {
    cat <<USAGE
usage: with-https.sh <command> [args...]
Runs the command so that git talks to GitHub over HTTPS with the gh login (or CODER_GH_TOKEN)
instead of SSH, so no YubiKey is needed. Examples:
  with-https.sh git pull
  with-https.sh gh issue develop 4 --name F/4/short-name --base main --checkout
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    "") usage >&2; exit 1 ;;
esac
exec "$@"
