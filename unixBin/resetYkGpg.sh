#!/usr/bin/env bash

#------------------------------------------------------------------------------
# resetYkGpg.sh - undo setYkGpg.sh on this machine
#
# Removes ONE YubiKey's key from this machine. The setup shared by all keys
# (SSH via gpg-agent, git signing) is removed only together with the LAST key.
#   ./unixBin/resetYkGpg.sh                  YubiKey plugged in - fingerprint
#                                            is read from the card
#   ./unixBin/resetYkGpg.sh <FINGERPRINT>    no YubiKey needed (e.g. lost key);
#                                            40 hex chars, see: gpg -K
# Re-apply with: ./unixBin/setYkGpg.sh
#
# Always (this key only):
#   1. Removes the card's auth subkey from ~/.gnupg/sshcontrol (added by older
#      setYkGpg.sh versions)
#   2. Unloads the SSH key (ssh-add -d) and deletes ~/.ssh/<FP>.ssh.pub
#   3. Deletes the key from the keyring: public key + card stubs (the
#      pointers to the YubiKey). Refuses if a REAL secret key for this
#      fingerprint is in the keyring, so a master key is never destroyed.
#
# Then, depending on which OTHER secret keys are still in the keyring:
#   - another YubiKey key (card stubs):
#       keep shared setup; if git user.signingkey pointed to the removed key,
#       switch it to the remaining YubiKey key
#   - only software keys (e.g. from setSwGpg.sh):
#       keep shared setup; if git user.signingkey pointed to the removed key,
#       switch it to the software key (commits/tags stay signed)
#   - none left - remove the shared setup:
#       - SET_YK_GPG block from ~/.gnupg/gpg-agent.conf (and from the shell
#         config, left by older versions), unixBin/env/LINK_gpg.env,
#         restart gpg-agent
#       - unset global git config: user.signingkey, commit.gpgsign,
#         tag.gpgsign, push.gpgsign, gpg.program
#
# Notes:
#   - Best effort: every step runs even if an earlier one fails or has
#     nothing to do, so it is safe to re-run. Exit code 1 if any step failed.
#   - Nothing on the YubiKey itself is changed.
#   - After the last key: open a new shell so SSH stops using gpg-agent.
#------------------------------------------------------------------------------

#---------------------------
# variables definitions
#---------------------------
EXIT_CODE=0
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(dirname "$0")
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"
GNUPG_DIR="$HOME/.gnupg"


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - resets GPG/SSH/git signing config set up by setYkGpg.sh"
    echo "usage: $0 [FINGERPRINT]"
    echo "  $0                - YubiKey must be plugged in, fingerprint is read from it"
    echo "  $0 <FINGERPRINT>  - no YubiKey needed, 40 hex chars (see: gpg -K)"
    echo "  $0 --help         - display this info"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo "$2"
    exit "$1"
}


checkYubiKeyPresence () {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace "$TRACE_INFO" "🔍 Checking for YubiKey..."
    if ! gpg --card-status &>/dev/null; then
        PrintUsageAndExitWithCode 1 "${RED}❌ YubiKey not detected. Insert your YubiKey or pass the key fingerprint: $0 <FINGERPRINT>${NC}"
    fi
    PrintTrace "$TRACE_INFO" "✅ YubiKey detected."
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


printYubiKeyInfo () {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace "$TRACE_INFO" "🔍 gpg --card-status"
    gpg --card-status
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


extractGpgAuthKey() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_KEY_FP="$2"
    local LCL_EXIT_CODE=0

    local LCL_AUTH_KEYGRIPS
    LCL_AUTH_KEYGRIPS=$(gpg --with-keygrip -K "$LCL_KEY_FP" 2>/dev/null | awk '/^ssb/ { t=0 } /\[A\]/ { t=1 } t && /Keygrip/ { print $3 }')
    [ -z "$LCL_AUTH_KEYGRIPS" ] && LCL_EXIT_CODE=1

    eval "$LCL_RETURN_VAR=\$LCL_AUTH_KEYGRIPS"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_AUTH_KEYGRIPS)"
    return $LCL_EXIT_CODE
}


removeGpgAuthKeyFromSshControl() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_SSHCONTROL_FILE="$GNUPG_DIR/sshcontrol"
    local LCL_AUTH_KEYGRIP
    local LCL_EXIT_CODE=0

    if [ ! -f "$LCL_SSHCONTROL_FILE" ]; then
        PrintTrace "$TRACE_INFO" "ℹ️  $LCL_SSHCONTROL_FILE does not exist - nothing to remove"
    elif ! extractGpgAuthKey LCL_AUTH_KEYGRIP "$LCL_KEY_FP"; then
        PrintTrace "$TRACE_INFO" "ℹ️  No auth subkey found for $LCL_KEY_FP in keyring - nothing to remove from $LCL_SSHCONTROL_FILE"
    elif ! grep -qF "$ABK_ENV_BEGIN $LCL_AUTH_KEYGRIP" "$LCL_SSHCONTROL_FILE"; then
        PrintTrace "$TRACE_INFO" "ℹ️  No entry for this key in $LCL_SSHCONTROL_FILE - nothing to remove"
    else
        PrintTrace "$TRACE_INFO" "🗑️  Removing GPG auth key from $LCL_SSHCONTROL_FILE"
        if AbkLib_RemoveEnvironmentSettings "$LCL_AUTH_KEYGRIP" "$LCL_SSHCONTROL_FILE"; then
            PrintTrace "$TRACE_INFO" "✅ GPG auth key removed from $LCL_SSHCONTROL_FILE"
        else
            PrintTrace "$TRACE_ERROR" "${RED}❌ Failed to remove GPG auth key from $LCL_SSHCONTROL_FILE${NC}"
            LCL_EXIT_CODE=1
        fi
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


getGpgFingerprint() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0

    local LCL_KEY_URL
    LCL_KEY_URL=$(gpg --card-status | awk -F': ' '/URL of public key/ {print $2}')
    [ -z "$LCL_KEY_URL" ] && PrintUsageAndExitWithCode 1 "${RED}❌ Could not extract public key URL from YubiKey.${NC}"
    PrintTrace "$TRACE_INFO" "🔍 Public key URL: $LCL_KEY_URL"

    local LCL_KEY_FP
    LCL_KEY_FP=$(basename "$LCL_KEY_URL" | sed 's/\.pub\.asc$//')
    [ -z "$LCL_KEY_FP" ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to extract fingerprint from URL: $LCL_KEY_URL${NC}"

    PrintTrace "$TRACE_INFO" "✅ Public key fingerprint: $LCL_KEY_FP"
    eval "$LCL_RETURN_VAR=\$LCL_KEY_FP"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


deleteSshPubKeyFile() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    local LCL_SSH_PUB_KEY_FILE="$HOME/.ssh/$LCL_KEY_FP.ssh.pub"

    if [ ! -f "$LCL_SSH_PUB_KEY_FILE" ]; then
        PrintTrace "$TRACE_INFO" "ℹ️  SSH public key file does not exist: $LCL_SSH_PUB_KEY_FILE - nothing to do"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return $LCL_EXIT_CODE
    fi

    PrintTrace "$TRACE_INFO" "🗑️  Unloading SSH key: $LCL_SSH_PUB_KEY_FILE"
    if SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket) ssh-add -d "$LCL_SSH_PUB_KEY_FILE"; then
        PrintTrace "$TRACE_INFO" "✅ SSH key unloaded"
    else
        # not loaded in the agent is fine - the key is removed from sshcontrol anyway
        PrintTrace "$TRACE_INFO" "${YLW}⚠️  SSH key was not loaded in gpg-agent - skipping unload${NC}"
    fi

    PrintTrace "$TRACE_INFO" "🗑️  Deleting SSH public key: $LCL_SSH_PUB_KEY_FILE"
    if rm "$LCL_SSH_PUB_KEY_FILE"; then
        PrintTrace "$TRACE_INFO" "✅ SSH public key file deleted"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Failed to delete SSH public key file${NC}"
        LCL_EXIT_CODE=1
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


resetSshGpgConfig() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0
    local LCL_GPG_AGENT_CONF_FILE="$GNUPG_DIR/gpg-agent.conf"
    local LCL_SHELL_CONFIG_FILE="$HOME/$ABK_USER_CONFIG_FILE_SHELL"
    local LCL_ENV_SCRIPT_NAME="SET_YK_GPG"
    local LCL_ENV_DIR
    LCL_ENV_DIR="$(cd "$SCRIPT_PATH" && pwd)/env"

    PrintTrace "$TRACE_INFO" "🔐 Resetting SSH key for GPG"
    # legacy: older setYkGpg.sh versions wrote the gpg shell env directly into the shell config
    if [ -f "$LCL_SHELL_CONFIG_FILE" ]; then
        AbkLib_RemoveEnvironmentSettings "$LCL_ENV_SCRIPT_NAME" "$LCL_SHELL_CONFIG_FILE" || LCL_EXIT_CODE=1
    fi

    PrintTrace "$TRACE_INFO" "🗑️  Removing $LCL_ENV_DIR/LINK_gpg.env (open a new shell to deactivate)"
    rm -f "$LCL_ENV_DIR/LINK_gpg.env"

    PrintTrace "$TRACE_INFO" "🔐 Disabling SSH support"
    if [ -f "$LCL_GPG_AGENT_CONF_FILE" ]; then
        if ! AbkLib_RemoveEnvironmentSettings "$LCL_ENV_SCRIPT_NAME" "$LCL_GPG_AGENT_CONF_FILE"; then
            PrintTrace "$TRACE_ERROR" "${RED}❌ Failed to remove SSH support from gpg-agent.conf${NC}"
            LCL_EXIT_CODE=1
        fi
    else
        PrintTrace "$TRACE_INFO" "ℹ️  gpg-agent.conf does not exist: $LCL_GPG_AGENT_CONF_FILE - nothing to remove"
    fi

    PrintTrace "$TRACE_INFO" "🔐 Restarting gpg-agent"
    if gpgconf --kill gpg-agent; then
        PrintTrace "$TRACE_INFO" "✅ gpg-agent stopped"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ gpg-agent failed to stop${NC}"
        LCL_EXIT_CODE=1
    fi
    sleep 1
    if gpgconf --launch gpg-agent; then
        PrintTrace "$TRACE_INFO" "✅ gpg-agent started"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ gpg-agent failed to start${NC}"
        LCL_EXIT_CODE=1
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


resetGitGpgSigningConfig() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0
    local LCL_GIT_KEYS=(user.signingkey commit.gpgsign tag.gpgsign push.gpgsign gpg.program)
    local LCL_GIT_KEY

    for LCL_GIT_KEY in "${LCL_GIT_KEYS[@]}"; do
        if ! git config --global --get "$LCL_GIT_KEY" >/dev/null; then
            PrintTrace "$TRACE_INFO" "ℹ️  git $LCL_GIT_KEY is not set - nothing to do"
        elif git config --global --unset "$LCL_GIT_KEY"; then
            PrintTrace "$TRACE_INFO" "✅ git $LCL_GIT_KEY unset"
        else
            PrintTrace "$TRACE_ERROR" "${RED}❌ git failed to unset $LCL_GIT_KEY${NC}"
            LCL_EXIT_CODE=1
        fi
    done

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Deletes the public key and its YubiKey card stubs from the keyring.
# Card stubs only point to the YubiKey (field 15 = card serial or '#') and are
# safe to delete. A real secret key (field 15 = '+') is never deleted.
removeKeyFromKeyRing() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0

    if ! gpg --list-keys "$LCL_KEY_FP" >/dev/null 2>&1; then
        PrintTrace "$TRACE_INFO" "ℹ️  No key found in keyring with ID: $LCL_KEY_FP - nothing to do"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return $LCL_EXIT_CODE
    fi

    local LCL_SECRET_LINES LCL_REAL_SECRETS
    LCL_SECRET_LINES=$(gpg --list-secret-keys --with-colons "$LCL_KEY_FP" 2>/dev/null | awk -F: '$1=="sec" || $1=="ssb"' || true)
    LCL_REAL_SECRETS=$(echo "$LCL_SECRET_LINES" | awk -F: '$15=="+"' || true)

    if [ -n "$LCL_REAL_SECRETS" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}❌ Keyring holds a REAL secret key for $LCL_KEY_FP (not just YubiKey stubs) - NOT deleting it.${NC}"
        PrintTrace "$TRACE_ERROR" "${RED}   Back it up first, then delete manually: gpg --delete-secret-and-public-key $LCL_KEY_FP${NC}"
        LCL_EXIT_CODE=1
    elif [ -n "$LCL_SECRET_LINES" ]; then
        PrintTrace "$TRACE_INFO" "🗑️  Removing public key and YubiKey card stubs: $LCL_KEY_FP"
        if gpg --batch --yes --delete-secret-and-public-key "$LCL_KEY_FP"; then
            PrintTrace "$TRACE_INFO" "✅ Key removed from keyring"
        else
            PrintTrace "$TRACE_ERROR" "${RED}❌ Failed to remove key from keyring${NC}"
            LCL_EXIT_CODE=1
        fi
    else
        PrintTrace "$TRACE_INFO" "🗑️  Removing public key: $LCL_KEY_FP"
        if gpg --batch --yes --delete-key "$LCL_KEY_FP"; then
            PrintTrace "$TRACE_INFO" "✅ Public key removed from keyring"
        else
            PrintTrace "$TRACE_ERROR" "${RED}❌ Failed to remove public key${NC}"
            LCL_EXIT_CODE=1
        fi
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Lists the OTHER keys (not $2) that still have secret material in the keyring,
# one "<FP> card|software" per line, YubiKey (card) keys first.
#   card:     a subkey is a YubiKey stub (field 15 = card serial number)
#   software: a real secret key or subkey is present (field 15 = '+')
# Keys with only offline stubs ('#') are not counted.
getRemainingSecretKeys() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXCLUDE_FP="$2"
    local LCL_REMAINING

    LCL_REMAINING=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: -v ex="$LCL_EXCLUDE_FP" '
        function flush() { if (fp != "" && fp != ex && type != "") print fp, type }
        $1 == "sec"                      { flush(); fp = ""; type = ""; want_fp = 1 }
        $1 == "fpr" && want_fp           { fp = $10; want_fp = 0 }
        ($1 == "sec" || $1 == "ssb") {
            if ($15 != "" && $15 != "#" && $15 != "+") type = "card"
            else if ($15 == "+" && type != "card")    type = "software"
        }
        END { flush() }' | sort -k2,2 || true)

    eval "$LCL_RETURN_VAR=\$LCL_REMAINING"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($(echo "$LCL_REMAINING" | grep -c . || true) keys)"
    return 0
}


# Keeps git signing working with a remaining key: if user.signingkey is unset
# or points to the removed key ($1), switch it to $2.
updateGitSigningKey() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_REMOVED_FP="$1"
    local LCL_NEW_FP="$2"
    local LCL_NEW_TYPE="$3"
    local LCL_EXIT_CODE=0
    local LCL_CURRENT LCL_NORMALIZED

    LCL_CURRENT=$(git config --global --get user.signingkey || true)
    # signingkey may be a short/long key ID or full fingerprint, with 0x or '!'
    LCL_NORMALIZED=$(echo "$LCL_CURRENT" | tr '[:lower:]' '[:upper:]' | sed -e 's/^0X//' -e 's/!$//')

    if [ -n "$LCL_NORMALIZED" ] && [[ "$LCL_REMOVED_FP" != *"$LCL_NORMALIZED" ]]; then
        PrintTrace "$TRACE_INFO" "ℹ️  git user.signingkey ($LCL_CURRENT) is not the removed key - leaving it"
    elif [ "$LCL_NEW_FP" = "$LCL_REMOVED_FP" ]; then
        PrintTrace "$TRACE_INFO" "ℹ️  $LCL_REMOVED_FP was not removed from the keyring - leaving git user.signingkey"
    elif git config --global user.signingkey "$LCL_NEW_FP"; then
        PrintTrace "$TRACE_INFO" "✅ git user.signingkey switched to remaining $LCL_NEW_TYPE key: $LCL_NEW_FP"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Failed to set git user.signingkey to $LCL_NEW_FP${NC}"
        LCL_EXIT_CODE=1
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


#---------------------------
# main
#---------------------------
if [ -f "$ABK_LIB_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ABK_LIB_FILE"
else
    echo "ERROR: cannot find $ABK_LIB_FILE"
    echo "  $ABK_LIB_FILE contains common definitions and functions"
    exit 1
fi

echo
PrintTrace "$TRACE_FUNCTION" "-> $0 ($*)"

PrintTrace "$TRACE_DEBUG" "SCRIPT_NAME = $SCRIPT_NAME"
PrintTrace "$TRACE_DEBUG" "SCRIPT_PATH = $SCRIPT_PATH"
PrintTrace "$TRACE_DEBUG" "ABK_LIB_FILE = $ABK_LIB_FILE"

[ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode 0
[ "$#" -gt 1 ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: invalid number of parameters, expected: 0 or 1${NC}"

if [ "$#" -eq 1 ]; then
    [[ "$1" =~ ^[0-9A-Fa-f]{40}$ ]] || PrintUsageAndExitWithCode 1 "${RED}ERROR: '$1' is not a 40 character hex fingerprint${NC}"
    KEY_FP=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    PrintTrace "$TRACE_INFO" "🔐 Using fingerprint from command line (no YubiKey needed): $KEY_FP"
else
    checkYubiKeyPresence
    printYubiKeyInfo
    getGpgFingerprint KEY_FP
fi
PrintTrace "$TRACE_INFO" "🔐 GPG key fingerprint: $KEY_FP"

# Best effort: run every step, remember failures
# 1. this key only
removeGpgAuthKeyFromSshControl "$KEY_FP" || EXIT_CODE=1
deleteSshPubKeyFile "$KEY_FP"            || EXIT_CODE=1
removeKeyFromKeyRing "$KEY_FP"           || EXIT_CODE=1

# 2. shared setup: keep it while any other secret key remains
# (no exclusion: a deleted key is gone anyway; a key whose deletion was refused
#  is still in the keyring and still in use, so it must count as remaining)
getRemainingSecretKeys REMAINING_KEYS ""
if [ -n "$REMAINING_KEYS" ]; then
    PrintTrace "$TRACE_INFO" "🔐 Other secret keys remain - keeping shared GPG/SSH/git signing setup:"
    echo "$REMAINING_KEYS" | while read -r LCL_FP LCL_TYPE; do PrintTrace "$TRACE_INFO" "     $LCL_FP ($LCL_TYPE)"; done
    read -r NEXT_FP NEXT_TYPE <<< "$(echo "$REMAINING_KEYS" | head -1)"
    updateGitSigningKey "$KEY_FP" "$NEXT_FP" "$NEXT_TYPE" || EXIT_CODE=1
    RESET_MSG="✅ Key $KEY_FP removed. Shared setup kept for the remaining keys."
else
    PrintTrace "$TRACE_INFO" "🔐 No other secret keys remain - removing shared GPG/SSH/git signing setup"
    resetSshGpgConfig                    || EXIT_CODE=1
    resetGitGpgSigningConfig             || EXIT_CODE=1
    RESET_MSG="✅ Last key removed - YubiKey GPG setup fully reset. Open a new shell to finish."
fi

if [ $EXIT_CODE -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "$RESET_MSG"
else
    PrintTrace "$TRACE_ERROR" "${RED}❌ Reset finished with errors - see messages above.${NC}"
fi

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
