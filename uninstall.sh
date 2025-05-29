#!/bin/bash

#---------------------------
# variables
#---------------------------
ABK_SHELL="${SHELL##*/}"
[ "$ABK_SHELL" != "bash" ] && [ "$ABK_SHELL" != "zsh" ] && echo "ERROR: $ABK_SHELL is not supported. Please consider using bash or zsh" && exit 1


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


__getJsonUninstallInstructions() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_JSON_FILE=$2
    local LCL_EXIT_CODE=0
    local LCL_OS_INSTRUCTIONS
    LCL_OS_INSTRUCTIONS=$(cat "$LCL_JSON_FILE")
    # PrintTrace $TRACE_DEBUG "LCL_JSON = $LCL_JSON"

    PrintTrace $TRACE_DEBUG "    LCL_RETURN_VAR = $LCL_RETURN_VAR"
    PrintTrace $TRACE_DEBUG "    LCL_JSON_FILE  = $LCL_JSON_FILE"
    PrintTrace $TRACE_DEBUG "    LCL_OS_INSTRUCTIONS = $LCL_OS_INSTRUCTIONS"

    eval "$LCL_RETURN_VAR"=\$LCL_OS_INSTRUCTIONS
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__removeAbkEnvToConfig() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_USER_CONFIG_FILE_SHELL=$1

    AbkLib_RemoveEnvironmentSettings "$ABK_ENV_NAME" "$LCL_USER_CONFIG_FILE_SHELL" || PrintTrace $TRACE_ERROR "${RED}ERROR: $HOME/$LCL_USER_CONFIG_FILE_SHELL file does not exist${NC}"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (0)"
    return 0
}


__markInstalledToolAsUninstalled() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_JSON_INSTALLATION_FILE_NAME=$1
    local LCL_INSTALLED_TYPE=$2
    local LCL_INSTALLED_ITEM=$3

    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_DEBUG "LCL_INSTALLED_TYPE = $LCL_INSTALLED_TYPE"
    PrintTrace $TRACE_DEBUG "LCL_INSTALLED_ITEM = $LCL_INSTALLED_ITEM"

    jq --arg type "$LCL_INSTALLED_TYPE" --arg item "$LCL_INSTALLED_ITEM" \
        'del(.[$type][$item]) | if (.[$type] == {}) then del(.[$type]) else . end' \
        "$INSTALLED_DIR/$LCL_JSON_INSTALLATION_FILE_NAME" > "$INSTALLED_DIR/$LCL_JSON_INSTALLATION_FILE_NAME.tmp" \
        && mv -f "$INSTALLED_DIR/$LCL_JSON_INSTALLATION_FILE_NAME.tmp" "$INSTALLED_DIR/$LCL_JSON_INSTALLATION_FILE_NAME"

    [ $? -eq 0 ] && PrintTrace $TRACE_DEBUG "$LCL_INSTALLED_TYPE/$LCL_INSTALLED_ITEM removed successfully."

    # Check if the entire file is empty and delete it
    if jq -e 'length == 0' "$INSTALLED_DIR/$LCL_JSON_INSTALLATION_FILE_NAME" | grep -q true; then
        rm "$INSTALLED_DIR/$LCL_JSON_INSTALLATION_FILE_NAME" \
            && PrintTrace $TRACE_DEBUG "File is empty, deleted: $INSTALLED_DIR/$LCL_JSON_INSTALLATION_FILE_NAME"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__uninstallItem() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} (hidden)"
    # PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_APP=$1
    local LCL_UNINSTALL_INSTRACTIONS=$2
    local LCL_EXIT_CODE=0
    PrintTrace $TRACE_INFO "${YLW}[$LCL_APP uninstalling ...]${NC}"

    while IFS= read -r UNINSTALL_STEP; do
        PrintTrace $TRACE_INFO "uninstall step: ${YLW}$UNINSTALL_STEP${NC}"
        eval "$UNINSTALL_STEP" || LCL_EXIT_CODE=1
    done <<< "$LCL_UNINSTALL_INSTRACTIONS"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__uninstallItemList() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} (hidden)"
    # PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_JSON_FILE_NAME=$1
    local LCL_INSTALLED_TYPE=$2
    local LCL_INSTRUCTIONS=$3
    local LCL_EXIT_CODE=0
    local LCL_INSTALLED_ITEM_LIST="null"

    # check if installed.json file exists
    if [ -e "$INSTALLED_DIR/$LCL_JSON_FILE_NAME" ]; then
        # check installed types
        LCL_INSTALLED_ITEM_LIST=$(jq -r ".$LCL_INSTALLED_TYPE // {} | keys_unsorted[]" "$INSTALLED_DIR/$LCL_JSON_FILE_NAME")
        # jq tool should be excluded
        LCL_INSTALLED_ITEM_LIST=$(echo "$LCL_INSTALLED_ITEM_LIST" | grep -v '^jq$')
        PrintTrace $TRACE_DEBUG "${ORG}Found installed: $LCL_INSTALLED_TYPE: ${LCL_INSTALLED_ITEM_LIST[*]}${NC}"
    fi

    # Check if LCL_INSTALLED_ITEM_LIST is not null before proceeding
    if [ "$LCL_INSTALLED_ITEM_LIST" != "null" ] && [ "$LCL_INSTALLED_ITEM_LIST" != "" ]; then
        PrintTrace $TRACE_INFO "${ORG}Uninstalling previously installed: ${LCL_INSTALLED_ITEM_LIST[*]}${NC}"
        local LCL_UNINSTALL_ITEMS=$(echo "$LCL_INSTRUCTIONS" | jq -r ".$LCL_INSTALLED_TYPE // {}")
        PrintTrace $TRACE_DEBUG "uninstall items: $LCL_UNINSTALL_ITEMS"

        while IFS= read -r LCL_INSTALLED_ITEM; do
            local UNINSTALL_STEPS=""
            PrintTrace $TRACE_DEBUG "LCL_INSTALLED_ITEM = $LCL_INSTALLED_ITEM"
            UNINSTALL_STEPS=$(echo "$LCL_UNINSTALL_ITEMS" | jq -er ".\"$LCL_INSTALLED_ITEM\" // [] | .[]")
            PrintTrace $TRACE_INFO "uninstall step list: ${YLW}$UNINSTALL_STEPS${NC}"
            __uninstallItem "$LCL_INSTALLED_ITEM" "$UNINSTALL_STEPS" \
                && __markInstalledToolAsUninstalled "$LCL_JSON_FILE_NAME" "$LCL_INSTALLED_TYPE" "$LCL_INSTALLED_ITEM" \
                || PrintTrace $TRACE_ERROR "${RED}ERROR: $LCL_INSTALLED_ITEM uninstall failed${NC}"
        done <<< "$LCL_INSTALLED_ITEM_LIST"
    else
        PrintTrace $TRACE_DEBUG "No installed $LCL_INSTALLED_TYPE found."
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__deleteBinDirLink() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]}"
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


#---------------------------
# main
#---------------------------
uninstall_abkEnv_main() {
    local MAIN_ABK_LIB_FILE="./unixBin/abkLib.sh"
    local MAIN_DEFAULT_JSON_FILE="./tools_min.json"
    local MAIN_JSON_INSTALLED_COUNT=0
    local MAIN_EXIT_CODE=0
    local MAIN_JSON_FILES
    local MAIN_TOOLS_JSON_FILE
    local MAIN_TOOLS_JSON


    [ -f $MAIN_ABK_LIB_FILE ] && . $MAIN_ABK_LIB_FILE || PrintUsageAndExitWithCode 1 "${RED}ERROR: $MAIN_ABK_LIB_FILE could not be found.${NC}"
    export TRACE_LEVEL=$TRACE_DEBUG
    # export TRACE_LEVEL=$TRACE_INFO
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"

    PrintTrace $TRACE_INFO "   ABK_SHELL         = $ABK_SHELL"
    PrintTrace $TRACE_INFO "   BIN_DIR           = $BIN_DIR"
    PrintTrace $TRACE_INFO "   HOME_BIN_DIR      = $HOME_BIN_DIR"
    PrintTrace $TRACE_INFO "   SH_BIN_DIR        = $SH_BIN_DIR"
    PrintTrace $TRACE_INFO "   SH_PACKAGES_DIR   = $SH_PACKAGES_DIR"
    PrintTrace $TRACE_INFO "   ABK_ENV_FILE      = $ABK_ENV_FILE"
    PrintTrace $TRACE_INFO "   HOME              = $HOME"
    PrintTrace $TRACE_INFO

    # is parameter --help?
    [ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode $ERROR_CODE_SUCCESS

    AbkLib_CheckPreRequisites || PrintUsageAndExitWithCode $ERROR_CODE_GENERAL_ERROR "${RED}ERROR: cannot proceed Pre-Requisites are not met${NC}"

    # Is number of parameters ok
    if [ "$#" -eq 0 ]; then
        PrintTrace $TRACE_INFO "No parameters provided, using default $MAIN_DEFAULT_JSON_FILE"
        MAIN_JSON_FILES=("$MAIN_DEFAULT_JSON_FILE")
    else
        MAIN_JSON_FILES=("$@")
    fi

    for MAIN_TOOLS_JSON_FILE in "${MAIN_JSON_FILES[@]}"; do

        # check if file exists
        [ ! -f "$INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE" ] && PrintTrace $TRACE_ERROR "${ORG}WARNING: File could NOT be found: $INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE${NC}" && continue
        # check if file is a JSON file
        [[ "$INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE" != *.json ]] && PrintTrace $TRACE_ERROR "${ORG}WARNING: Skipping non-JSON file: $INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE${NC}" && continue
        [ ! -f "$INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE" ] && PrintTrace $TRACE_ERROR "${ORG}WARNING: JSON file $MAIN_TOOLS_JSON_FILE was not used to install${NC}" && continue

        PrintTrace $TRACE_INFO "\n${BLU}Processing $INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE${NC}"
        # get uninstall json instructions
        __getJsonUninstallInstructions MAIN_TOOLS_JSON "$INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE" || { PrintTrace $TRACE_ERROR "${RED}ERROR: Could not get correct uninstall instructions from file: $INSTALLED_DIR/$MAIN_TOOLS_JSON_FILE${NC}"; continue; }
        PrintTrace $TRACE_DEBUG "MAIN_TOOLS_JSON = $MAIN_TOOLS_JSON"

        __uninstallItemList "$MAIN_TOOLS_JSON_FILE" "$INSTALLED_FONTS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __uninstallItemList $INSTALLED_FONTS failed"
        __uninstallItemList "$MAIN_TOOLS_JSON_FILE" "$INSTALLED_APPS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __uninstallItemList $INSTALLED_APPS failed"
        __uninstallItemList "$MAIN_TOOLS_JSON_FILE" "$INSTALLED_TOOLS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __uninstallItemList $INSTALLED_TOOLS failed"

        ((MAIN_JSON_INSTALLED_COUNT++))
    done

    PrintTrace $TRACE_INFO "Uninstalled json files count: $MAIN_JSON_INSTALLED_COUNT"
    if [ $MAIN_JSON_INSTALLED_COUNT -eq 0 ]; then
        PrintUsageAndExitWithCode 0 "${ORG}INFO: Nothing to uninstall${NC}"
    fi

    local MAIN_ALL_JSON_FILES_EMPTY=true
    local MAIN_JSON_INSTALLATION_FILE

    PrintTrace $TRACE_INFO "Checking installation JSON files in $INSTALLED_DIR ..."
    for MAIN_JSON_INSTALLATION_FILE in "$INSTALLED_DIR"/*.json; do
        [ ! -f "$MAIN_JSON_INSTALLATION_FILE" ] && { PrintTrace $TRACE_ERROR "${ORG}WARNING: File could NOT be found: $MAIN_JSON_INSTALLATION_FILE${NC}"; continue; }

        if ! jq -e 'type == "object" and (keys | length == 0)' "$MAIN_JSON_INSTALLATION_FILE" > /dev/null 2>&1; then
            PrintTrace $TRACE_INFO "${ORG}INFO: File is not empty: $MAIN_JSON_INSTALLATION_FILE${NC}"
            MAIN_ALL_JSON_FILES_EMPTY=false
        else
            PrintTrace $TRACE_INFO "${ORG}INFO: File is empty: $MAIN_JSON_INSTALLATION_FILE${NC}"
            rm "$MAIN_JSON_INSTALLATION_FILE"
        fi
    done

    if $MAIN_ALL_JSON_FILES_EMPTY; then
        PrintTrace $TRACE_INFO "${ORG}INFO: All JSON files are empty. Removing config ...${NC}"
        __removeAbkEnvToConfig "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || PrintTrace $TRACE_ERROR "${RED}ERROR:${NC} __removeAbkEnvToConfig $HOME/$ABK_USER_CONFIG_FILE_SHELL failed. Exited with: $?"
        __deleteBinDirLink || PrintTrace $TRACE_ERROR "${RED}ERROR:${NC} __deleteBinDirLink failed with $?"
        exec $ABK_SHELL
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (0)"
    return 0
}

echo ""
echo "-> $0 ($*)"

# shellcheck disable=SC2068
uninstall_abkEnv_main $@
LCL_EXIT_CODE=$?

echo "<- $0 (0)"
exit $LCL_EXIT_CODE
