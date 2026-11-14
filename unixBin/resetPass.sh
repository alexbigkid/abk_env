#!/usr/bin/env bash

#------------------------------------------------------------------------------
# resetPass.sh - undo setPass.sh on this machine
#
# Removes the local password store clones and ~/.envrc_common. No parameters.
# Re-apply with: ./unixBin/setPass.sh
#
# What it does:
#   1. Per store (same list as setPass.sh):
#      - deletes the clone ONLY if nothing would be lost: no uncommitted
#        changes, no stash, nothing unpushed (it fetches first). Otherwise the
#        clone is kept and you are told why.
#      - after the clone is deleted: deletes <store root>/.envrc if setPass.sh
#        created it, and the store root folder if it is then empty
#   2. Removes the ~/.envrc_common symlink (a real file is left alone)
#
# Notes:
#   - The stores stay safe on the git remote - setPass.sh clones them again.
#   - Best effort: every step runs; exit code 1 if anything was kept/failed.
#------------------------------------------------------------------------------

#---------------------------
# variables definitions
#---------------------------
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=0
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(dirname "$0")
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"
ENVRC_COMMON_TARGET="$HOME/.envrc_common"
ENVRC_MARKER="# created by abk_env/unixBin/setPass.sh"

# name | git remote | clone dir | store dir - keep in sync with setPass.sh
PASS_STORES=(
    "abk|git@github.com:alexbigkid/psws_abk.git|$HOME/.psws_abk|$HOME/.psws_abk/secrets"
    "ta|git@github.com:alexbigkid/psws_ta.git|$HOME/.psws_ta/secrets|$HOME/.psws_ta/secrets"
)


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - removes pass password store clones and ~/.envrc_common"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo "$2"
    exit "$1"
}


# Delete the clone only if it is fully committed and pushed.
removeStoreClone() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_NAME="$1"
    local LCL_CLONE_DIR="$2"
    local LCL_EXIT_CODE=0

    # guard: only ever delete ~/.psws_* paths
    if [[ -z "$LCL_CLONE_DIR" || "$LCL_CLONE_DIR" != "$HOME"/.psws_* ]]; then
        PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] refusing to delete unexpected path: '$LCL_CLONE_DIR'${NC}"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (1)"
        return 1
    fi

    if [ ! -e "$LCL_CLONE_DIR" ]; then
        PrintTrace "$TRACE_INFO" "ℹ️  [$LCL_NAME] $LCL_CLONE_DIR does not exist - nothing to do"
    elif [ ! -d "$LCL_CLONE_DIR/.git" ]; then
        PrintTrace "$TRACE_INFO" "${YLW}⚠️  [$LCL_NAME] $LCL_CLONE_DIR is not a git clone - leaving it alone${NC}"
        LCL_EXIT_CODE=1
    else
        local LCL_REASON=""
        git -C "$LCL_CLONE_DIR" fetch --quiet 2>/dev/null || LCL_REASON="git fetch failed (offline?)"
        [ -z "$LCL_REASON" ] && [ -n "$(git -C "$LCL_CLONE_DIR" status --porcelain)" ] && LCL_REASON="uncommitted changes"
        [ -z "$LCL_REASON" ] && [ -n "$(git -C "$LCL_CLONE_DIR" stash list)" ] && LCL_REASON="stashed changes"
        if [ -z "$LCL_REASON" ]; then
            local LCL_AHEAD
            LCL_AHEAD=$(git -C "$LCL_CLONE_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo "no-upstream")
            [ "$LCL_AHEAD" = "no-upstream" ] && LCL_REASON="branch has no upstream"
            [ "$LCL_AHEAD" != "no-upstream" ] && [ "$LCL_AHEAD" -gt 0 ] && LCL_REASON="$LCL_AHEAD unpushed commit(s)"
        fi

        if [ -n "$LCL_REASON" ]; then
            PrintTrace "$TRACE_INFO" "${YLW}⚠️  [$LCL_NAME] keeping $LCL_CLONE_DIR: $LCL_REASON${NC}"
            LCL_EXIT_CODE=1
        elif rm -rf "$LCL_CLONE_DIR"; then
            PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] deleted clone $LCL_CLONE_DIR (all changes are on the remote)"
        else
            PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] failed to delete $LCL_CLONE_DIR${NC}"
            LCL_EXIT_CODE=1
        fi
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Remove the .envrc setPass.sh created (outside the clone) and the empty root.
removeStoreRoot() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_NAME="$1"
    local LCL_STORE_DIR="$2"
    local LCL_ROOT_DIR
    LCL_ROOT_DIR=$(dirname "$LCL_STORE_DIR")
    local LCL_ENVRC="$LCL_ROOT_DIR/.envrc"

    if [ -f "$LCL_ENVRC" ] && grep -qxF "$ENVRC_MARKER" "$LCL_ENVRC"; then
        rm -f "$LCL_ENVRC"
        PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] removed $LCL_ENVRC"
    fi
    if [ -d "$LCL_ROOT_DIR" ] && [ -z "$(ls -A "$LCL_ROOT_DIR")" ]; then
        rmdir "$LCL_ROOT_DIR" && PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] removed empty $LCL_ROOT_DIR"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


unlinkEnvrcCommon() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    if [ -L "$ENVRC_COMMON_TARGET" ]; then
        rm "$ENVRC_COMMON_TARGET"
        PrintTrace "$TRACE_INFO" "✅ removed symlink $ENVRC_COMMON_TARGET"
    elif [ -e "$ENVRC_COMMON_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "ℹ️  $ENVRC_COMMON_TARGET is a real file, not a symlink - leaving it"
    else
        PrintTrace "$TRACE_INFO" "ℹ️  $ENVRC_COMMON_TARGET does not exist - nothing to do"
    fi
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
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

[ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode 0
[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS${NC}"

for STORE in "${PASS_STORES[@]}"; do
    IFS='|' read -r STORE_NAME STORE_REMOTE STORE_CLONE_DIR STORE_DIR <<< "$STORE"
    PrintTrace "$TRACE_INFO" "🔐 [$STORE_NAME] $STORE_DIR ($STORE_REMOTE)"
    # keep the store's .envrc while its clone is kept
    if removeStoreClone "$STORE_NAME" "$STORE_CLONE_DIR"; then
        removeStoreRoot "$STORE_NAME" "$STORE_DIR"
    else
        EXIT_CODE=1
    fi
done

unlinkEnvrcCommon

if [ $EXIT_CODE -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "✅ Password store setup removed."
else
    PrintTrace "$TRACE_ERROR" "${RED}❌ Finished with warnings/errors - see messages above.${NC}"
fi

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
