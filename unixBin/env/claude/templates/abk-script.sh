#!/usr/bin/env bash

#---------------------------
# variables definitions
#---------------------------
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=${EXPECTED_PARAMS}
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(dirname "$0")
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"

#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - ${SCRIPT_DESCRIPTION}"
    echo "usage: $0 ${USAGE_PARAMS}"
    echo "  $0 --help   - display this info"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo "$2"
    exit "$1"
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

# Check for help parameter
[ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode 0

# Check parameter count
[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS${NC}"

set -e

# TODO: Implement main script logic here

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE