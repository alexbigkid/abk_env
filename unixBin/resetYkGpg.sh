#!/usr/bin/env bash
# export passwords to external file

#---------------------------
# variables definitions
#---------------------------
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=0
SCRIPT_NAME=$(basename $0)
SCRIPT_PATH=$(dirname $0)
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"
GNUPG_DIR="$HOME/.gnupg"


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - resets up GPG/SSH config with YubiKey"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo $2
    exit $1
}


checkYubiKeyPresence () {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace $TRACE_INFO "🔍 Checking for YubiKey..."
    if ! gpg --card-status &>/dev/null; then
        PrintUsageAndExitWithCode 1 "${RED}❌ YubiKey not detected. Please insert your YubiKey and try again.${NC}"
    fi
    PrintTrace $TRACE_INFO "✅ YubiKey detected."
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


printYubiKeyInfo () {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace $TRACE_INFO "🔍 gpg --card-status"
    gpg --card-status
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


extractGpgAuthKey() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_KEY_FP="$2"
    local LCL_EXIT_CODE=0

    local LCL_AUTH_KEYGRIPS
    LCL_AUTH_KEYGRIPS=$(gpg --with-keygrip -K "$LCL_KEY_FP" | awk '/^ssb/ { t=0 } /\[A\]/ { t=1 } t && /Keygrip/ { print $3 }')
    [ -z "$LCL_AUTH_KEYGRIPS" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_AUTH_KEYGRIPS
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_AUTH_KEYGRIPS)"
    return $LCL_EXIT_CODE
}


removeGpgAuthKeyFromSshControl() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_AUTH_KEYGRIP="$1"
    local LCL_SSHCONTROL_FILE="$GNUPG_DIR/sshcontrol"
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_INFO "🗑️  Removing GPG auth key to $LCL_SSHCONTROL_FILE"
    AbkLib_RemoveEnvironmentSettings "$LCL_AUTH_KEYGRIP" "$LCL_SSHCONTROL_FILE"
    LCL_EXIT_CODE=$?

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace $TRACE_ERROR "❌ Failed to remove GPG key from $LCL_SSHCONTROL_FILE"
    else
        PrintTrace $TRACE_INFO "✅ GPG key removed from $LCL_SSHCONTROL_FILE"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


getGpgFingerprint() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0

    # local LCL_KEY_URL=$(gpg --card-status | grep "URL of public key" | awk '{print $6}')
    # PrintTrace $TRACE_INFO "✅ Public key fingerprint: $LCL_KEY_FP"
    local LCL_KEY_URL=$(gpg --card-status | awk -F': ' '/URL of public key/ {print $2}')
    [ -z "$LCL_KEY_URL" ] && PrintUsageAndExitWithCode 1 "${RED}❌ Could not extract public key URL from YubiKey.${NC}"
    PrintTrace $TRACE_INFO "🔍 Public key URL: $LCL_KEY_URL"

    local LCL_KEY_FP=$(basename "$LCL_KEY_URL" | sed 's/\.pub\.asc$//')
    [ -z "$LCL_KEY_FP" ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to extract fingerprint from URL: $LCL_KEY_URL${NC}"

    PrintTrace $TRACE_INFO "✅ Public key fingerprint: $LCL_KEY_FP"
    eval $LCL_RETURN_VAR=\$LCL_KEY_FP
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


deleteSshPubKeyFile() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    local LCL_SSH_DIR="$HOME/.ssh"
    local LCL_SSH_PUB_KEY_FILE="$LCL_KEY_FP.ssh.pub"

    PrintTrace $TRACE_INFO "🗑️  Unloading SSH public key: $LCL_SSH_DIR/$LCL_SSH_PUB_KEY_FILE"
    PrintTrace $TRACE_INFO "🔐 Available SSH keys:"
    ssh-add -d "$LCL_SSH_DIR/$LCL_SSH_PUB_KEY_FILE"
    [ $? -ne 0 ] && PrintTrace $TRACE_ERROR "${RED}❌ Failed to unload SSH public key${NC}"

    PrintTrace $TRACE_INFO "🗑️  Deleting SSH public key: $LCL_SSH_DIR/$LCL_SSH_PUB_KEY_FILE"
    if [ -f "$LCL_SSH_DIR/$LCL_SSH_PUB_KEY_FILE" ]; then
        rm "$LCL_SSH_DIR/$LCL_SSH_PUB_KEY_FILE"
        [ $? -ne 0 ] && LCL_EXIT_CODE=1
    else
        PrintTrace $TRACE_WARNING "⚠️ SSH public key file does not exist: $LCL_SSH_DIR/$LCL_SSH_PUB_KEY_FILE"
    fi

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace $TRACE_ERROR "❌ Failed to delete SSH public key file"
    else
        PrintTrace $TRACE_INFO "✅ SSH public key file successfully deleted"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


resetSshGpgConfig() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    local LCL_GPG_AGENT_CONF_FILE="$GNUPG_DIR/gpg-agent.conf"
    local LCL_ENV_SCRIPT_NAME="SET_YK_GPG"

    PrintTrace $TRACE_INFO "🔐 Resetting SSH key for GPG"
    AbkLib_RemoveEnvironmentSettings "$LCL_ENV_SCRIPT_NAME" "$HOME/$ABK_USER_CONFIG_FILE_SHELL"

    PrintTrace $TRACE_INFO "🔐 Reloading environment"
    if [ "$ABK_SHELL" = "zsh" ]; then
        zsh -c "source $HOME/$ABK_USER_CONFIG_FILE_SHELL"
    elif [ "$ABK_SHELL" = "bash" ]; then
        source "$HOME/$ABK_USER_CONFIG_FILE_SHELL"
    else
        PrintTrace $TRACE_ERROR "${RED}❌ Unsupported shell: $ABK_SHELL${NC}"
    fi

    PrintTrace $TRACE_INFO "🔐 Disabling SSH support"
    if [ -f "$LCL_GPG_AGENT_CONF_FILE" ]; then
        AbkLib_RemoveEnvironmentSettings "$LCL_ENV_SCRIPT_NAME" "$LCL_GPG_AGENT_CONF_FILE"
        [ $? -ne 0 ] && PrintTrace $TRACE_ERROR "${RED}❌ Failed to remove SSH support from gpg-agent.conf${NC}"
    else
        PrintTrace $TRACE_WARNING "⚠️ gpg-agent.conf file does not exist: $LCL_GPG_AGENT_CONF_FILE"
    fi

    PrintTrace $TRACE_INFO "🔐 Restarting gpg-agent"
    gpgconf --kill gpg-agent
    [ $? -eq 0 ] && PrintTrace $TRACE_INFO "✅ gpg-agent stopped" || PrintTrace $TRACE_ERROR "${RED}❌ gpg-agent failed to stop${NC}"
    sleep 1
    gpgconf --launch gpg-agent
    [ $? -eq 0 ] && PrintTrace $TRACE_INFO "✅ gpg-agent started" || PrintTrace $TRACE_ERROR "${RED}❌ gpg-agent failed to start${NC}"

    PrintTrace $TRACE_INFO "🔐 Available SSH keys:"
    ssh-add -L | grep cardno: || PrintTrace $TRACE_INFO "${YLW}⚠️  No GPG-based SSH key found.${NC}"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}



resetGitGpgSigningConfig() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_INFO "🔐 Unsetting git user.signingkey: $LCL_KEY_FP"
    git config --global --unset user.signingkey
    [ $? -ne 0 ] && PrintTrace $TRACE_ERROR "${YLW}⚠️ git failed to unset sign key${NC}"

    PrintTrace $TRACE_INFO "🔐 Unsetting git commit.gpgsign"
    git config --global --unset commit.gpgsign
    [ $? -ne 0 ] && PrintTrace $TRACE_ERROR "${RED}⚠️ git failed to unset sign commits${NC}"

    PrintTrace $TRACE_INFO "🔐 Unsetting git tag.gpgsign"
    git config --global --unset tag.gpgsign
    [ $? -ne 0 ] && PrintTrace $TRACE_ERROR "${RED}⚠️ git failed to unset sign tags${NC}"

    PrintTrace $TRACE_INFO "🔐 Unsetting git push.gpgsign"
    git config --global --unset push.gpgsign
    [ $? -ne 0 ] && PrintTrace $TRACE_ERROR "${RED}⚠️ git failed to unset sign push${NC}"

    PrintTrace $TRACE_INFO "🔐 Unsetting up gpg.program"
    git config --global --unset gpg.program
    [ $? -ne 0 ] && PrintTrace $TRACE_ERROR "${RED}⚠️ git failed to unset gpg tool${NC}"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setGpgKeyTrustToUnknown() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0

    if [[ -z "$LCL_KEY_FP" ]]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ No key fingerprint provided. Aborting.${NC}"
    fi

    PrintTrace $TRACE_INFO "🔐 Setting trust level of key $LCL_KEY_FP to ultimate"

    expect <<EOF
        log_user 1
        set timeout 30
        spawn gpg --edit-key $LCL_KEY_FP
        expect "gpg>" { send "trust\r" }
        expect {
            "Your decision?" { send "1\r" }  # unknown
            timeout { puts "❌ Timeout during trust selection"; exit 1 }
        }
        expect "gpg>" { send "quit\r" }
        expect eof
EOF

    LCL_EXIT_CODE=$?

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace $TRACE_ERROR "❌ Failed to unset trust level for $LCL_KEY_FP"
    else
        PrintTrace $TRACE_INFO "✅ Trust level set to unknown for key $LCL_KEY_FP"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


removePublicKeyFromKeyRing() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0

    if gpg --list-keys "$LCL_KEY_FP" > /dev/null 2>&1; then
        PrintTrace $TRACE_INFO "🗑️  Removing GPG public key: $LCL_KEY_FP"
        gpg --batch --yes --delete-key "$LCL_KEY_FP"
        if [ $? -eq 0 ]; then
            PrintTrace $TRACE_INFO "✅ Public key removed successfully"
        else
            PrintTrace $TRACE_ERROR "${RED}❌ Failed to remove public key${NC}"
            LCL_EXIT_CODE=1
        fi
    else
        PrintTrace $TRACE_INFO "⚠️  No public key found with ID: $LCL_KEY_FP"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


#---------------------------
# main
#---------------------------
if [ -f $ABK_LIB_FILE ]; then
    source $ABK_LIB_FILE
else
    echo "ERROR: cannot find $ABK_LIB_FILE"
    echo "  $ABK_LIB_FILE contains common definitions and functions"
    exit 1
fi

echo
PrintTrace $TRACE_FUNCTION "-> $0 ($*)"

PrintTrace $TRACE_DEBUG "SCRIPT_NAME = $SCRIPT_NAME"
PrintTrace $TRACE_DEBUG "SCRIPT_PATH = $SCRIPT_PATH"
PrintTrace $TRACE_DEBUG "ABK_LIB_FILE = $ABK_LIB_FILE"

[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS"
set -e

checkYubiKeyPresence
printYubiKeyInfo

getGpgFingerprint KEY_FP
PrintTrace $TRACE_INFO "🔐 GPG key fingerprint: $KEY_FP"
extractGpgAuthKey AUTH_SUB_KEY_FP "$KEY_FP" && removeGpgAuthKeyFromSshControl "$AUTH_SUB_KEY_FP"
deleteSshPubKeyFile "$KEY_FP"
resetSshGpgConfig "$KEY_FP"
resetGitGpgSigningConfig "$KEY_FP"
setGpgKeyTrustToUnknown "$KEY_FP"
removePublicKeyFromKeyRing "$KEY_FP"

PrintTrace $TRACE_FUNCTION "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
