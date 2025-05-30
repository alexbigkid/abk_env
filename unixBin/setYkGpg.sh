#!/usr/bin/env bash

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
    echo "$0 - sets up GPG/SSH config with YubiKey"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo $2
    exit $1
}


checkPrerequisiteToolsAreInstalled () {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    if [ "$ABK_UNIX_TYPE" = "macOS" ]; then
        declare -a required_tools=(gpg gpg-agent yq ykman pinentry-mac)
    elif [ "$ABK_UNIX_TYPE" = "linux" ]; then
        declare -a required_tools=(gpg gpg-agent yq ykman pinentry)
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Unknown OS type: $ABK_UNIX_TYPE${NC}"
    fi

    for tool in "${required_tools[@]}"; do
      if ! command -v "$tool" &>/dev/null; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Required tool '$tool' is not installed. Please install: $tool. Aborting.${NC}"
      fi
    done
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


checkYubiKeyPresence () {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace "$TRACE_INFO" "🔍 Checking for YubiKey..."
    if ! gpg --card-status &>/dev/null; then
        PrintUsageAndExitWithCode 1 "${RED}❌ YubiKey not detected. Please insert your YubiKey and try again.${NC}"
    fi
    PrintTrace "$TRACE_INFO" "✅ YubiKey detected."
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


printYubiKeyInfo () {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace "$TRACE_INFO" "🔍 gpg --card-status"
    gpg --card-status
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


fetchPublicKeyFromYubiKey() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    local LCL_MAX_RETRIES=3
    local LCL_RETRY_COUNT=0
    local LCL_RETRY_DELAY=4 # seconds

    PrintTrace "$TRACE_INFO" "🔍 Fetching public key from YubiKey"
    # local public_key=$(gpg --card-status | grep "public key" | awk '{print $6}')
    # PrintTrace "$TRACE_INFO" "✅ Public key: $public_key"

    while [ $LCL_RETRY_COUNT -le $LCL_MAX_RETRIES ]; do
        PrintTrace "$TRACE_INFO" "🔍 Fetching public key attempt: $LCL_RETRY_COUNT"

        expect <<EOF
            log_user 1
            set timeout 60
            spawn gpg --card-edit
            expect {
                "gpg/card>" { send "fetch\r" }
                timeout { puts "❌ Timeout while starting card edit"; exit 1 }
            }
            expect {
                -re "gpg: WARNING: unable to fetch URI.*" {
                    puts "❌ Failed to fetch public key from URL"
                    exit 1
                }
                "gpg/card>" {
                    send "quit\r"
                }
                timeout {
                    puts "❌ Timeout while waiting for fetch to complete"
                    exit 1
                }
            }
            expect eof
EOF
        LCL_EXIT_CODE=$?

        if [ $LCL_EXIT_CODE -eq 0 ]; then
            PrintTrace "$TRACE_INFO" "✅ Public key fetched successfully on attempt: $LCL_RETRY_COUNT"
            break
        elif [ $LCL_RETRY_COUNT -lt $LCL_MAX_RETRIES ]; then
            PrintTrace "$TRACE_INFO" "❌ Attempt: $LCL_RETRY_COUNT failed to fetch public. Retrying..."
        else
            PrintTrace "$TRACE_INFO" "❌ Failed to fetch public key after attempts: $LCL_RETRY_COUNT. Exit code: $LCL_EXIT_CODE"
            break
        fi
        ((LCL_RETRY_COUNT++))
        sleep $LCL_RETRY_DELAY
    done

    [ $LCL_EXIT_CODE -ne 0 ] && PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to fetch public key from YubiKey. Aborting.${NC}"
    PrintTrace "$TRACE_INFO" "✅ Public key fetched successfully."
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


getGpgFingerprint() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0

    # local LCL_KEY_URL=$(gpg --card-status | grep "URL of public key" | awk '{print $6}')
    # PrintTrace "$TRACE_INFO" "✅ Public key fingerprint: $LCL_KEY_FP"
    local LCL_KEY_URL=$(gpg --card-status | awk -F': ' '/URL of public key/ {print $2}')
    [ -z "$LCL_KEY_URL" ] && PrintUsageAndExitWithCode 1 "${RED}❌ Could not extract public key URL from YubiKey.${NC}"
    PrintTrace "$TRACE_INFO" "🔍 Public key URL: $LCL_KEY_URL"

    local LCL_KEY_FP=$(basename "$LCL_KEY_URL" | sed 's/\.pub\.asc$//')
    [ -z "$LCL_KEY_FP" ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to extract fingerprint from URL: $LCL_KEY_URL${NC}"

    PrintTrace "$TRACE_INFO" "✅ Public key fingerprint: $LCL_KEY_FP"
    eval $LCL_RETURN_VAR=\$LCL_KEY_FP
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setGpgKeyTrustToUltimate() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0

    if [[ -z "$LCL_KEY_FP" ]]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ No key fingerprint provided. Aborting.${NC}"
    fi

    PrintTrace "$TRACE_INFO" "🔐 Setting trust level of key $LCL_KEY_FP to ultimate"

    expect <<EOF
        log_user 1
        set timeout 30
        spawn gpg --edit-key $LCL_KEY_FP
        expect "gpg>" { send "trust\r" }
        expect {
            "Your decision?" { send "5\r" }  # ultimate
            timeout { puts "❌ Timeout during trust selection"; exit 1 }
        }
        expect {
            "Do you really want to set this key to ultimate trust?" { send "y\r" }
            timeout { puts "❌ Timeout during trust confirmation"; exit 1 }
        }
        expect "gpg>" { send "quit\r" }
        expect eof
EOF

    LCL_EXIT_CODE=$?

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to set trust level for $LCL_KEY_FP"
    else
        PrintTrace "$TRACE_INFO" "✅ Trust level set to ultimate for key $LCL_KEY_FP"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setGitGpgSigningConfig() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0

    PrintTrace "$TRACE_INFO" "🔐 Setting gpg long key format"
    gpg --list-secret-keys --keyid-format=long
    [ $? -ne 0 ] && PrintTrace "$TRACE_ERROR" "${RED}❌ gpg failed to set long format${NC}"

    PrintTrace "$TRACE_INFO" "🔐 Setting git user.signingkey: $LCL_KEY_FP"
    git config --global user.signingkey "$LCL_KEY_FP"
    [ $? -ne 0 ] && PrintTrace "$TRACE_ERROR" "${RED}❌ git failed to set sign key${NC}"

    PrintTrace "$TRACE_INFO" "🔐 Setting git commit.gpgsign to true"
    git config --global commit.gpgsign true
    [ $? -ne 0 ] && PrintTrace "$TRACE_ERROR" "${RED}❌ git failed to set sign commits${NC}"

    PrintTrace "$TRACE_INFO" "🔐 Setting git tag.gpgsign to true"
    git config --global tag.gpgsign true
    [ $? -ne 0 ] && PrintTrace "$TRACE_ERROR" "${RED}❌ git failed to set sign tags${NC}"

    PrintTrace "$TRACE_INFO" "🔐 Setting git push.gpgsign to false"
    git config --global push.gpgsign false
    [ $? -ne 0 ] && PrintTrace "$TRACE_ERROR" "${RED}❌ git failed to set sign push${NC}"

    local LCL_GPG_PROGRAM_PATH
    LCL_GPG_PROGRAM_PATH=$(which gpg)
    PrintTrace "$TRACE_INFO" "🔐 Setting up gpg.program to $LCL_GPG_PROGRAM_PATH"
    git config --global gpg.program "$LCL_GPG_PROGRAM_PATH"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


extractGpgAuthKey() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_KEY_FP="$2"
    local LCL_EXIT_CODE=0

    local LCL_AUTH_KEYGRIPS
    LCL_AUTH_KEYGRIPS=$(gpg --with-keygrip -K "$LCL_KEY_FP" | awk '/^ssb/ { t=0 } /\[A\]/ { t=1 } t && /Keygrip/ { print $3 }')
    [ -z "$LCL_AUTH_KEYGRIPS" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_AUTH_KEYGRIPS
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_AUTH_KEYGRIPS)"
    return $LCL_EXIT_CODE
}


setSshGpgConfig() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    local LCL_GPG_AGENT_CONTENT_ARRAY=()
    local LCL_SHELL_CONTENT_ARRAY=()
    local LCL_GPG_AGENT_CONFIG="$GNUPG_DIR/gpg-agent.conf"
    local LCL_ENV_SCRIPT_NAME="SET_YK_GPG"
    local LCL_PIN_ENTRY_PATH

    PrintTrace "$TRACE_INFO" "🔐 Setting GPG directory"
    mkdir -p "$GNUPG_DIR"
    chmod 700 "$GNUPG_DIR"
    touch "$LCL_GPG_AGENT_CONFIG"
    chmod 600 "$LCL_GPG_AGENT_CONFIG"

    PrintTrace "$TRACE_INFO" "🔐 Enabling SSH support"
    [ "$ABK_UNIX_TYPE" = "macOS" ] && LCL_PIN_ENTRY_PATH=$(which pinentry-mac) || LCL_PIN_ENTRY_PATH=$(which pinentry)
    PrintTrace "$TRACE_INFO" "🔐 Pinentry program: $LCL_PIN_ENTRY_PATH"
    [ -z "$LCL_PIN_ENTRY_PATH" ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to find pinentry program.${NC}"
    PrintTrace "$TRACE_INFO" "🔐 Checking $LCL_GPG_AGENT_CONFIG"
    grep -q "enable-ssh-support" "$LCL_GPG_AGENT_CONFIG" || LCL_GPG_AGENT_CONTENT_ARRAY+=("enable-ssh-support")
    PrintTrace "$TRACE_INFO" "🔐 enable-ssh-support: ${LCL_GPG_AGENT_CONTENT_ARRAY[@]}"
    grep -q "default-cache-ttl 600" "$LCL_GPG_AGENT_CONFIG" || LCL_GPG_AGENT_CONTENT_ARRAY+=("default-cache-ttl 600")
    PrintTrace "$TRACE_INFO" "🔐 default-cache-ttl: ${LCL_GPG_AGENT_CONTENT_ARRAY[@]}"
    grep -q "max-cache-ttl 7200" "$LCL_GPG_AGENT_CONFIG" || LCL_GPG_AGENT_CONTENT_ARRAY+=("max-cache-ttl 7200")
    PrintTrace "$TRACE_INFO" "🔐 max-cache-ttl: ${LCL_GPG_AGENT_CONTENT_ARRAY[@]}"
    grep -q "pinentry-program $LCL_PIN_ENTRY_PATH" "$LCL_GPG_AGENT_CONFIG" || LCL_GPG_AGENT_CONTENT_ARRAY+=("pinentry-program $LCL_PIN_ENTRY_PATH")
    PrintTrace "$TRACE_INFO" "🔐 pinentry-program: ${LCL_GPG_AGENT_CONTENT_ARRAY[@]}"
    [ ${#LCL_GPG_AGENT_CONTENT_ARRAY[@]} -ne 0 ] && AbkLib_AddEnvironmentSettings "$LCL_ENV_SCRIPT_NAME" "$LCL_GPG_AGENT_CONFIG" "${LCL_GPG_AGENT_CONTENT_ARRAY[@]}"

    PrintTrace "$TRACE_INFO" "🔐 Restarting gpg-agent"
    gpgconf --kill gpg-agent
    [ $? -eq 0 ] && PrintTrace "$TRACE_INFO" "✅ gpg-agent stopped" || PrintTrace "$TRACE_ERROR" "${RED}❌ gpg-agent failed to stop${NC}"
    sleep 1
    gpgconf --launch gpg-agent
    [ $? -eq 0 ] && PrintTrace "$TRACE_INFO" "✅ gpg-agent started" || PrintTrace "$TRACE_ERROR" "${RED}❌ gpg-agent failed to start${NC}"

    PrintTrace "$TRACE_INFO" "🔐 Setting up SSH key for GPG"
    grep -q 'export GPG_TTY=$(tty)' "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || LCL_SHELL_CONTENT_ARRAY+=('export GPG_TTY=$(tty)')
    grep -q 'export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)' "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || LCL_SHELL_CONTENT_ARRAY+=('export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)')
    grep -q 'gpgconf --kill gpg-agent' "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || LCL_SHELL_CONTENT_ARRAY+=('gpgconf --kill gpg-agent')
    grep -q 'gpgconf --launch gpg-agent' "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || LCL_SHELL_CONTENT_ARRAY+=('gpgconf --launch gpg-agent')
    [ ${#LCL_SHELL_CONTENT_ARRAY[@]} -ne 0 ] && AbkLib_AddEnvironmentSettings "$LCL_ENV_SCRIPT_NAME" "$HOME/$ABK_USER_CONFIG_FILE_SHELL" "${LCL_SHELL_CONTENT_ARRAY[@]}"

    PrintTrace "$TRACE_INFO" "🔐 Reloading environment"
    if [ "$ABK_SHELL" = "zsh" ]; then
        zsh -c "source $HOME/$ABK_USER_CONFIG_FILE_SHELL"
    elif [ "$ABK_SHELL" = "bash" ]; then
        source "$HOME/$ABK_USER_CONFIG_FILE_SHELL"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Unsupported shell: $ABK_SHELL${NC}"
    fi

    PrintTrace "$TRACE_INFO" "🔐 Available SSH keys:"
    ssh-add -L | grep cardno: || PrintTrace "$TRACE_INFO" "${YLW}⚠️  No GPG-based SSH key found.${NC}"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


addGpgAuthKeyToSshControl() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_AUTH_KEYGRIP="$1"
    local LCL_SSHCONTROL_FILE="$GNUPG_DIR/sshcontrol"
    local LCL_EXIT_CODE=0

    touch "$LCL_SSHCONTROL_FILE"
    chmod 600 "$LCL_SSHCONTROL_FILE"
    local LCL_CONTENT_TO_ADD_ARRAY=(
        "$LCL_AUTH_KEYGRIP"
    )

    PrintTrace "$TRACE_INFO" "🔐 Adding GPG auth key to $LCL_SSHCONTROL_FILE"
    AbkLib_AddEnvironmentSettings "$LCL_AUTH_KEYGRIP" "$LCL_SSHCONTROL_FILE" "${LCL_CONTENT_TO_ADD_ARRAY[@]}"
    LCL_EXIT_CODE=$?

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to add GPG key to $LCL_SSHCONTROL_FILE"
    else
        PrintTrace "$TRACE_INFO" "✅ GPG key added to $LCL_SSHCONTROL_FILE"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


exportSshPubKeyFromYubikey() {
    PrintTrace "$TRACE_FUNCTION" "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    local LCL_SSH_DIR="$HOME/.ssh"

    mkdir -p "$LCL_SSH_DIR"
    chmod 700 "$LCL_SSH_DIR"

    PrintTrace "$TRACE_INFO" "🔐 Exporting SSH public key from YubiKey"
    gpg --export-ssh-key "$LCL_KEY_FP" > "$LCL_SSH_DIR/$LCL_KEY_FP.ssh.pub"
    LCL_EXIT_CODE=$?

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to export SSH public key from YubiKey"
    else
        PrintTrace "$TRACE_INFO" "✅ SSH public key exported successfully from YubiKey"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
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
PrintTrace "$TRACE_FUNCTION" "-> $0 ($*)"

PrintTrace "$TRACE_DEBUG" "SCRIPT_NAME = $SCRIPT_NAME"
PrintTrace "$TRACE_DEBUG" "SCRIPT_PATH = $SCRIPT_PATH"
PrintTrace "$TRACE_DEBUG" "ABK_LIB_FILE = $ABK_LIB_FILE"

[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS"
set -e

checkPrerequisiteToolsAreInstalled
checkYubiKeyPresence

printYubiKeyInfo
fetchPublicKeyFromYubiKey
getGpgFingerprint KEY_FP
setGpgKeyTrustToUltimate "$KEY_FP"
setGitGpgSigningConfig "$KEY_FP"
setSshGpgConfig "$KEY_FP"
extractGpgAuthKey AUTH_SUB_KEY_FP "$KEY_FP" && addGpgAuthKeyToSshControl "$AUTH_SUB_KEY_FP"
exportSshPubKeyFromYubikey "$KEY_FP"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
