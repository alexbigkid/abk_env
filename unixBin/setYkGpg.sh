#!/usr/bin/env bash
# export passwords to external file

#---------------------------
# variables definitions
#---------------------------
TRACE=1
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=0
SCRIPT_NAME=$(basename $0)
SCRIPT_PATH=$(dirname $0)
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - extracts pass passwords"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo "  <pass path to extract> - name of password directory to extract passwords for"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo $2
    exit $1
}


checkPrerequisiteToolsAreInstalled () {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    declare -a required_tools=(gpg gpg-agent yq ykman)
    for tool in "${required_tools[@]}"; do
      if ! command -v "$tool" &>/dev/null; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Required tool '$tool' is not installed. Please install: $tool. Aborting.${NC}"
      fi
    done
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
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


fetchPublicKeyFromYubiKey() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace $TRACE_INFO "🔍 Fetching public key from YubiKey"
    # local public_key=$(gpg --card-status | grep "public key" | awk '{print $6}')
    # PrintTrace $TRACE_INFO "✅ Public key: $public_key"
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

    [ $LCL_EXIT_CODE -ne 0 ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to fetch public key from YubiKey. Aborting.${NC}"
    PrintTrace $TRACE_INFO "✅ Public key fetched successfully."
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

checkPrerequisiteToolsAreInstalled
checkYubiKeyPresence

printYubiKeyInfo
fetchPublicKeyFromYubiKey


PrintTrace $TRACE_FUNCTION "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
