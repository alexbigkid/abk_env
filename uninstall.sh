#!/bin/bash

#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode() {
    echo "$0 will delete ABK environment, which has been installed previously with: ./install.sh"
    echo "the script $0 must be called without any parameters"
    echo "usage: $0"
    echo "  $0 --help           - display this info"
    echo
    echo -e $2
    echo "errorExitCode = $1"
    exit $1
}


__removeAbkEnvToConfig() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_USER_CONFIG_FILE_SHELL=$1

    AbkLib_RemoveEnvironmentSettings "$ABK_ENV_NAME" "$LCL_USER_CONFIG_FILE_SHELL" || PrintUsageAndExitWithCode $ERROR_CODE_NEEDED_FILE_DOES_NOT_EXIST "${RED}ERROR: $HOME/$LCL_USER_CONFIG_FILE_SHELL file does not exist${NC}"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (0)"
    return 0
}


__markInstalledToolAsUninstalled() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_INSTALLED_TYPE=$1
    local LCL_INSTALLED_ITEM=$2
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_DEBUG "LCL_INSTALLED_TYPE = $LCL_INSTALLED_TYPE"
    PrintTrace $TRACE_DEBUG "LCL_INSTALLED_ITEM = $LCL_INSTALLED_ITEM"

    jq --arg type "$LCL_INSTALLED_TYPE" --arg item "$LCL_INSTALLED_ITEM" \
        'del(.[$type][$item]) | if (.[$type] == {}) then del(.[$type]) else . end' \
        "$INSTALLED_DIR/$INSTALLED_FILE" > "$INSTALLED_DIR/$INSTALLED_FILE.tmp" \
        && mv "$INSTALLED_DIR/$INSTALLED_FILE.tmp" "$INSTALLED_DIR/$INSTALLED_FILE"

    [ $? -eq 0 ] && PrintTrace $TRACE_DEBUG "$LCL_INSTALLED_TYPE/$LCL_INSTALLED_ITEM removed successfully."

    # Check if the entire file is empty and delete it
    if jq -e 'length == 0' "$INSTALLED_DIR/$INSTALLED_FILE" | grep -q true; then
        rm "$INSTALLED_DIR/$INSTALLED_FILE"
        [ $? -eq 0 ] && PrintTrace $TRACE_DEBUG "File is empty. Deleted."
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__uninstallItem() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_UNINSTALL_TYPE=$1
    local LCL_APP=$2
    local LCL_UNINSTALL_INSTRACTIONS=$3
    local LCL_IS_APP_INSTALLED=0
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_INFO "${YLW}[$LCL_APP uninstalling ...]${NC}"
    local TOOL_INSTALLED=$TRUE

    while IFS= read -r UNINSTALL_STEP; do
        PrintTrace $TRACE_INFO "uninstall step: ${YLW}$UNINSTALL_STEP${NC}"
        eval "$UNINSTALL_STEP" || LCL_EXIT_CODE=1
    done <<< "$LCL_UNINSTALL_INSTRACTIONS"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__uninstallItemList() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTALLED_TYPE=$1
    local LCL_INSTRACTIONS=$2
    local LCL_EXIT_CODE=0
    local LCL_INSTALLED_ITEM_LIST=
    local LCL_ITEM="${LCL_INSTALLED_TYPE//installed_/}"
    PrintTrace $TRACE_DEBUG "LCL_ITEM = $LCL_ITEM"

    # check if installed.json file exists
    if [ -e "$INSTALLED_DIR/$INSTALLED_FILE" ]; then
        # check installed types
        LCL_INSTALLED_ITEM_LIST=$(jq -r ".$LCL_INSTALLED_TYPE // {} | keys_unsorted[]" "$INSTALLED_DIR/$INSTALLED_FILE")
        # jq tool should be excluded
        LCL_INSTALLED_ITEM_LIST=$(echo "$LCL_INSTALLED_ITEM_LIST" | grep -v '^jq$')
        PrintTrace $TRACE_DEBUG "${ORG}Installed type: $LCL_INSTALLED_TYPE: ${LCL_INSTALLED_ITEM_LIST[@]}${NC}"
    fi

    # Check if LCL_INSTALLED_ITEM_LIST is not null before proceeding
    if [ "$LCL_INSTALLED_ITEM_LIST" != "null" ] && [ "$LCL_INSTALLED_ITEM_LIST" != "" ]; then
        PrintTrace $TRACE_INFO "${ORG}Uninstalling previously installed type: ${LCL_INSTALLED_ITEM_LIST[@]}${NC}"
        local LCL_UNINSTALL_ITEMS=$(echo "$LCL_INSTRACTIONS" | jq -r ".$LCL_ITEM.uninstall")

        while IFS= read -r LCL_INSTALLED_ITEM; do
            UNINSTALL_STEPS=$(echo "$LCL_UNINSTALL_ITEMS" | jq -r ".\"$LCL_INSTALLED_ITEM\"[]")
            PrintTrace $TRACE_INFO "uninstall step list: ${YLW}$UNINSTALL_STEPS${NC}"
            __uninstallItem "$LCL_INSTALLED_TYPE" "$LCL_INSTALLED_ITEM" "$UNINSTALL_STEPS" \
                && __markInstalledToolAsUninstalled "$LCL_INSTALLED_TYPE" "$LCL_INSTALLED_ITEM" \
                || PrintTrace $TRACE_ERROR "${RED}ERROR: $LCL_INSTALLED_ITEM uninstall failed${NC}"
        done <<< "$LCL_INSTALLED_ITEM_LIST"
    else
        PrintTrace $TRACE_DEBUG "No installed $LCL_INSTALLED_TYPE found."
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__deleteBinDirLink() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_CURRENT_DIR=$PWD
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_DEBUG "LCL_CURRENT_DIR = $LCL_CURRENT_DIR"
    if [ -d $HOME_BIN_DIR ]; then
        PrintTrace $TRACE_INFO "[Deleting directory link $HOME_BIN_DIR to $LCL_CURRENT_DIR/$SH_BIN_DIR ...]"
        rm $HOME_BIN_DIR || LCL_EXIT_CODE=$?
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__uninstallRequiredTools() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTRACTIONS=$1
    local LCL_INSTALLED_TYPE=$INSTALLED_TOOLS
    local LCL_EXIT_CODE=0
    local LCL_INSTALLED_ITEM_LIST=

    # check if installed.json file exists
    if [ -e "$INSTALLED_DIR/$INSTALLED_FILE" ]; then
        LCL_INSTALLED_ITEM_LIST=$(jq -r ".$LCL_INSTALLED_TYPE // {} | keys_unsorted[]" "$INSTALLED_DIR/$INSTALLED_FILE")
        PrintTrace $TRACE_DEBUG "${ORG}Installed type: $LCL_INSTALLED_TYPE: ${LCL_INSTALLED_ITEM_LIST[@]}${NC}"
    fi

    if [ "$LCL_INSTALLED_ITEM_LIST" != "null" ] && [ "$LCL_INSTALLED_ITEM_LIST" != "" ]; then
        PrintTrace $TRACE_INFO "${ORG}Uninstalling jq: ${LCL_INSTALLED_ITEM_LIST[@]}${NC}"
        local LCL_UNINSTALL_ITEMS=$(echo "$LCL_INSTRACTIONS" | jq -r ".tools.uninstall")

        while IFS= read -r LCL_INSTALLED_ITEM; do
            UNINSTALL_STEPS=$(echo "$LCL_UNINSTALL_ITEMS" | jq -r ".\"$LCL_INSTALLED_ITEM\"[]")
            PrintTrace $TRACE_INFO "uninstall step list: ${YLW}$UNINSTALL_STEPS${NC}"
            __uninstallItem "$LCL_INSTALLED_TYPE" "$LCL_INSTALLED_ITEM" "$UNINSTALL_STEPS" \
                && __markInstalledToolAsUninstalled "$LCL_INSTALLED_TYPE" "$LCL_INSTALLED_ITEM" \
                || PrintTrace $TRACE_ERROR "${RED}ERROR: $LCL_INSTALLED_ITEM uninstall failed${NC}"
        done <<< "$LCL_INSTALLED_ITEM_LIST"
    else
        PrintTrace $TRACE_DEBUG "No installed $LCL_INSTALLED_TYPE found."
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


#---------------------------
# main
#---------------------------
uninstall_abkEnv_main() {
    local MAIN_ABK_LIB_FILE="./unixBin/abkLib.sh"
    local MAIN_TOOLS_JSON_FILE="./tools.json"
    local MAIN_ABK_UNINSTALL_OH_MY="__uninstall_oh_my"
    [ -f $MAIN_ABK_LIB_FILE ] && . $MAIN_ABK_LIB_FILE || PrintUsageAndExitWithCode 1 "${RED}ERROR:${NC} $MAIN_ABK_LIB_FILE could not be found."
    [ -f $MAIN_TOOLS_JSON_FILE ] || PrintUsageAndExitWithCode 1 "${RED}ERROR:${NC} $MAIN_TOOLS_JSON_FILE file could not be found."
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"

    PrintTrace $TRACE_INFO "   [BIN_DIR           = $BIN_DIR]"
    PrintTrace $TRACE_INFO "   [HOME_BIN_DIR      = $HOME_BIN_DIR]"
    PrintTrace $TRACE_INFO "   [SH_BIN_DIR        = $SH_BIN_DIR]"
    PrintTrace $TRACE_INFO "   [SH_PACKAGES_DIR   = $SH_PACKAGES_DIR]"
    PrintTrace $TRACE_INFO "   [ABK_ENV_FILE      = $ABK_ENV_FILE]"
    PrintTrace $TRACE_INFO "   [HOME              = $HOME]"
    PrintTrace $TRACE_INFO

    # is parameter --help?
    [ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode $ERROR_CODE_SUCCESS
    # Is number of parameters ok
    [ "$#" -ne 0 ] && PrintUsageAndExitWithCode $ERROR_CODE_GENERAL_ERROR "${RED}ERROR: invalid number of parameters${NC}"

    AbkLib_CheckPreRequisites || PrintUsageAndExitWithCode $ERROR_CODE_GENERAL_ERROR "${RED}ERROR: cannot proceed Pre-Requisites are not met${NC}"

    # get uninstall json instructions
    local MAIN_TOOLS_JSON=
    AbkLib_GetJsonInstructions MAIN_TOOLS_JSON "$MAIN_TOOLS_JSON_FILE" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} Could not get correct install instructions from file: ${MAIN_TOOLS_JSON_FILE[*]}"
    PrintTrace $TRACE_DEBUG "MAIN_TOOLS_JSON = $MAIN_TOOLS_JSON"

    # check unix (MacOS/Linux version supported)
    AbkLib_CheckInstallationCompability "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} The installation is not supported."

    __uninstallItemList "$INSTALLED_FONTS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __uninstallItemList $INSTALLED_FONTS failed"
    __uninstallItemList "$INSTALLED_APPS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __uninstallItemList $INSTALLED_APPS failed"
    __uninstallItemList "$INSTALLED_TOOLS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __uninstallItemList $INSTALLED_TOOLS failed"

    __removeAbkEnvToConfig "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __removeAbkEnvToConfig $HOME/$ABK_USER_CONFIG_FILE_SHELL failed"
    __deleteBinDirLink || PrintTrace $TRACE_ERROR "${RED}ERROR:${NC} __deleteBinDirLink failed with $?"

    AbkLib_SourceEnvironment "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_SourceEnvironment $HOME/$ABK_USER_CONFIG_FILE_SHELL failed"
    __uninstallRequiredTools "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __uninstallRequiredTools failed"

    exec ${SHELL##*/}

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (0)"
    return 0
}

echo ""
echo "-> $0 ($@)"

uninstall_abkEnv_main $@
LCL_EXIT_CODE=$?

echo "<- $0 (0)"
exit $LCL_EXIT_CODE
