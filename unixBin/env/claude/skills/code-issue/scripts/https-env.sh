# shellcheck shell=bash

#------------------------------------------------------------------------------
# https-env.sh - make every git network operation of this shell use HTTPS instead of SSH.
# Sourced by with-https.sh and commit-push.sh, not executed.
#
# The remote of a repo may be SSH (git@github.com:...), which needs the user's own SSH
# key (for example on a YubiKey). The coder must not depend on it: through git's
# environment config the SSH URLs of github.com are rewritten to HTTPS and the credentials
# come from the gh login of the user. Settings the caller already has in GIT_CONFIG_* are
# kept, and the credential helper applies to github.com only. The setting reaches git
# processes started by gh as well (gh issue develop --checkout).
#------------------------------------------------------------------------------

HTTPS_BASE="https://github.com/"
SSH_SCP_PREFIX="git@github.com:"
SSH_URL_PREFIX="ssh://git@github.com/"
CREDENTIAL_KEY="credential.https://github.com.helper"
CREDENTIAL_HELPER="!gh auth git-credential"

# Append one git setting to the environment config, keeping those the caller already set.
add_git_env_config() {
    local index=${GIT_CONFIG_COUNT:-0}
    export "GIT_CONFIG_KEY_$index=$1" "GIT_CONFIG_VALUE_$index=$2"
    export GIT_CONFIG_COUNT=$((index + 1))
}

add_git_env_config "url.${HTTPS_BASE}.insteadOf" "$SSH_SCP_PREFIX"
add_git_env_config "url.${HTTPS_BASE}.insteadOf" "$SSH_URL_PREFIX"
add_git_env_config "$CREDENTIAL_KEY" ""
add_git_env_config "$CREDENTIAL_KEY" "$CREDENTIAL_HELPER"
