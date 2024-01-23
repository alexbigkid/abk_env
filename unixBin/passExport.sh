#!/usr/bin/env bash
# export passwords to external file

#---------------------------
# variables definitions
#---------------------------
TRACE=1
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=1
SCRIPT_NAME=$(basename $0)
SCRIPT_PATH=$(dirname $0)
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"
PE_PSWD_APP_DIR=${PASSWORD_STORE_DIR:-$HOME/.password-store}


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{

    echo "-> PrintUsageAndExitWithCode ($@)"
    echo "$0 - extracts pass passwords"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo "  <pass path to extract> - name of password directory to extract passwords for"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo $2
    exit $1
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
AbkLib_PrintTrace $TRACE_FUNCTION "-> $0 ($@)"

AbkLib_PrintTrace $TRACE_DEBUG "SCRIPT_NAME = $SCRIPT_NAME"
AbkLib_PrintTrace $TRACE_DEBUG "SCRIPT_PATH = $SCRIPT_PATH"
AbkLib_PrintTrace $TRACE_DEBUG "ABK_LIB_FILE = $ABK_LIB_FILE"

[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS"
PSWD_DIR=$1

AbkLib_PrintTrace $TRACE_DEBUG "PE_PSWD_APP_DIR = $PE_PSWD_APP_DIR"

pushd $PE_PSWD_APP_DIR
[ ! -d "$PSWD_DIR" ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: pass directory does not exist: $PSWD_DIR${NC}"

GPG_FILES=$(find $PSWD_DIR -type f -name "*.gpg")
[ -z "$GPG_FILES" ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: no gpg files found in pass directory: $PSWD_DIR${NC}"
# AbkLib_PrintTrace $TRACE_DEBUG "GPG_FILES = $GPG_FILES"
popd

{
    for PSWD_LINE in $GPG_FILES; do
        PSWD_KEY=${PSWD_LINE%.gpg}
        PSWD_VALUE=$(pass $PSWD_KEY)
        echo "$PSWD_KEY: $PSWD_VALUE"
    done
} > $PSWD_DIR.txt


AbkLib_PrintTrace $TRACE_FUNCTION "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
