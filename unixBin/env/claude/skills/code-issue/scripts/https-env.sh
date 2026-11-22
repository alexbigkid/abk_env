# shellcheck shell=bash

#------------------------------------------------------------------------------
# https-env.sh - make every git network operation of this shell use HTTPS instead of SSH.
# Sourced by with-https.sh and commit-push.sh, not executed.
#
# The remote of the repo may be SSH (git@github.com:...), which needs the user's YubiKey.
# The coder must not depend on it: through git's environment config the SSH URL is
# rewritten to HTTPS and the credentials come from the gh login (or CODER_GH_TOKEN).
# The setting reaches git processes started by gh as well (gh issue develop --checkout).
#------------------------------------------------------------------------------

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0="url.https://github.com/.insteadOf" GIT_CONFIG_VALUE_0="git@github.com:"
export GIT_CONFIG_KEY_1="url.https://github.com/.insteadOf" GIT_CONFIG_VALUE_1="ssh://git@github.com/"
export GIT_CONFIG_KEY_2="credential.helper" GIT_CONFIG_VALUE_2=""
export GIT_CONFIG_KEY_3="credential.helper" GIT_CONFIG_VALUE_3="!gh auth git-credential"
if [ -n "${CODER_GH_TOKEN:-}" ]; then export GH_TOKEN=$CODER_GH_TOKEN; fi
