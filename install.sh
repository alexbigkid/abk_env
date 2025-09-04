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
    echo "$0 will create ABK environment"
    echo "the script $0 must be called without any parameters"
    echo "usage: $0"
    echo "  $0 --help           - display this info"
    echo
    echo -e "$2"
    echo "errorExitCode = $1"
    exit $1
}


__getJsonInstallInstructions() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_JSON_FILE=$2
    local LCL_EXIT_CODE=0
    local LCL_JSON_KEY=".$ABK_UNIX_TYPE"
    local LCL_JSON
    LCL_JSON=$(cat "$LCL_JSON_FILE")
    # PrintTrace "$TRACE_DEBUG" "LCL_JSON = $LCL_JSON"

    PrintTrace "$TRACE_DEBUG" "    LCL_RETURN_VAR = $LCL_RETURN_VAR"
    PrintTrace "$TRACE_DEBUG" "    LCL_JSON_FILE  = $LCL_JSON_FILE"
    PrintTrace "$TRACE_DEBUG" "    LCL_JSON_KEY   = $LCL_JSON_KEY"
    PrintTrace "$TRACE_DEBUG" "    LCL_JSON       = $LCL_JSON"

    if [ "$ABK_UNIX_TYPE" == "linux" ]; then
        AbkLib_GetIdLike_linux LINUX_ID_LIKE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetIdLike_linux failed"
        LCL_JSON_KEY="${LCL_JSON_KEY}.${LINUX_ID_LIKE}"
    fi

    local LCL_OS_INSTRUCTIONS
    LCL_OS_INSTRUCTIONS=$(echo "$LCL_JSON" | jq -r "$LCL_JSON_KEY")
    PrintTrace "$TRACE_DEBUG" "    LCL_OS_INSTRUCTIONS = $LCL_OS_INSTRUCTIONS"

    eval "$LCL_RETURN_VAR"=\$LCL_OS_INSTRUCTIONS
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__addAbkEnvToConfig() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_USER_CONFIG_FILE_SHELL=$1
    local LCL_CONTENT_TO_ADD_ARRAY=(
        "if [ -f $ABK_ENV_FILE ]; then"
        "    . $ABK_ENV_FILE"
        "fi"
    )

    if [ ! -f "$LCL_USER_CONFIG_FILE_SHELL" ]; then
        echo "   [Creating user profile: $LCL_USER_CONFIG_FILE_SHELL ...]"
        touch "$LCL_USER_CONFIG_FILE_SHELL"
    fi

    AbkLib_AddEnvironmentSettings "$ABK_ENV_NAME" "$LCL_USER_CONFIG_FILE_SHELL" "${LCL_CONTENT_TO_ADD_ARRAY[@]}" || PrintUsageAndExitWithCode $ERROR_CODE_NEEDED_FILE_DOES_NOT_EXIST "${RED}ERROR: failed update environment in $LCL_USER_CONFIG_FILE_SHELL${NC}"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


__createInstalledFile() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_INSTALL_JSON_FILE=$1
    local LCL_EXIT_CODE=0

    # ensure there is a directory to store the package information
    mkdir -p $INSTALLED_DIR || LCL_EXIT_CODE=$?
    [ ! -f "$INSTALLED_DIR/$LCL_INSTALL_JSON_FILE" ] && echo {} > $INSTALLED_DIR/$LCL_INSTALL_JSON_FILE

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_RETURN_VAL)"
    return $LCL_RETURN_VAL
}


__updatePackageManager() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTRUCTIONS=$1
    local LCL_EXIT_CODE=0

    # update brew / apt repository and packages
    local LCL_UPDATE_PACKAGES
    LCL_UPDATE_PACKAGES=$(echo "$LCL_INSTRUCTIONS" | jq -r ".update_packages[]")
    if [ "$LCL_UPDATE_PACKAGES" != "" ]; then
        PrintTrace "$TRACE_INFO" "${ORG}[Updating packages]${NC}"
        while IFS= read -r LCL_UPDATE_PACKAGE; do
            PrintTrace "$TRACE_DEBUG" "${ORG}$LCL_UPDATE_PACKAGE${NC}"
            eval $LCL_UPDATE_PACKAGE
        done <<< "$LCL_UPDATE_PACKAGES"
    else
        PrintTrace "$TRACE_CRITICAL" "Did NOT find the update_packages section"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__installItem() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} (hidden)"
    # PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_JSON_INSTALLATION_FILE_NAME=$1
    local LCL_INSTALL_TYPE=$2
    local LCL_ITEM=$3
    local LCL_CHECK_INSTRUCTIONS=$4
    local LCL_INSTALL_INSTRUCTIONS=$5
    local LCL_UNINSTALL_INSTRUCTIONS=$6
    local LCL_DESCRIPTIONS=$7
    local LCL_IS_APP_INSTALLED=1
    local LCL_EXIT_CODE=0

    PrintTrace "$TRACE_DEBUG" "LCL_ITEM                    = $LCL_ITEM"
    PrintTrace "$TRACE_DEBUG" "LCL_INSTALL_INSTRUCTIONS    = $LCL_INSTALL_INSTRUCTIONS"
    PrintTrace "$TRACE_DEBUG" "LCL_INSTALL_TYPE            = $LCL_INSTALL_TYPE"
    PrintTrace "$TRACE_DEBUG" "LCL_CHECK_INSTRUCTIONS      = $LCL_CHECK_INSTRUCTIONS"

    # PrintTrace "$TRACE_DEBUG" "PATH = $PATH"
    # PrintTrace "$TRACE_DEBUG" "PWD  = $PWD"
    while IFS= read -r LCL_CHECK_STEP; do
        PrintTrace "$TRACE_DEBUG" "LCL_CHECK_STEP = $LCL_CHECK_STEP"
        EVAL_CHECK_STEP=$(eval "$LCL_CHECK_STEP" 2>/dev/null)
        PrintTrace "$TRACE_DEBUG" "EVAL_CHECK_STEP = $EVAL_CHECK_STEP"
        if [ "$EVAL_CHECK_STEP" != "" ]; then
            LCL_IS_APP_INSTALLED=0
        fi
        PrintTrace "$TRACE_DEBUG" "LCL_IS_APP_INSTALLED = $LCL_IS_APP_INSTALLED"
    done <<< "$LCL_CHECK_INSTRUCTIONS"

    if [ $LCL_IS_APP_INSTALLED -eq 1 ]; then
        PrintTrace "$TRACE_INFO" "${YLW}[$LCL_ITEM installing ...]${NC}"
        # Display tool description if available
        if [ "$LCL_DESCRIPTIONS" != "" ] && [ "$LCL_DESCRIPTIONS" != "null" ]; then
            local LCL_TOOL_DESCRIPTION
            LCL_TOOL_DESCRIPTION=$(echo "$LCL_DESCRIPTIONS" | jq -r ".\"$LCL_ITEM\"" 2>/dev/null)
            if [ "$LCL_TOOL_DESCRIPTION" != "null" ] && [ "$LCL_TOOL_DESCRIPTION" != "" ]; then
                PrintTrace "$TRACE_INFO" "${YLW} $LCL_ITEM: $LCL_TOOL_DESCRIPTION${NC}"
            fi
        fi
        while IFS= read -r INSTALL_STEP; do
            eval "$INSTALL_STEP"
            LCL_EXIT_CODE=$?
            if [ $LCL_EXIT_CODE -ne 0 ]; then
                PrintTrace "$TRACE_ERROR" "${RED}ERROR: $INSTALL_STEP failed with $LCL_EXIT_CODE${NC}"
                break
            fi
        done <<< "$LCL_INSTALL_INSTRUCTIONS"

        PrintTrace "$TRACE_INFO" "${YLW}[$LCL_ITEM marking uninstalling steps ...]${NC}"
        AbkLib_WriteUninstallSteps "$LCL_JSON_INSTALLATION_FILE_NAME" "$LCL_INSTALL_TYPE" "$LCL_ITEM" "$LCL_UNINSTALL_INSTRUCTIONS"
    else
        PrintTrace "$TRACE_INFO" "${GRN}$LCL_ITEM already installed${NC}"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__installItemList() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} (hidden)"
    # PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_JSON_FILE_NAME=$1
    local LCL_INSTALLED_TYPE=$2
    local LCL_INSTRUCTIONS=$3
    local LCL_EXIT_CODE=0
    local LCL_ITEM="${LCL_INSTALLED_TYPE//installed_/}"

   # install items
    local LCL_CHECK_ITEMS
    LCL_CHECK_ITEMS=$(echo $LCL_INSTRUCTIONS | jq -r ".$LCL_ITEM.check")
    PrintTrace "$TRACE_DEBUG" "LCL_CHECK_ITEMS = $LCL_CHECK_ITEMS"
    local LCL_INSTALL_ITEMS
    LCL_INSTALL_ITEMS=$(echo $LCL_INSTRUCTIONS | jq -r ".$LCL_ITEM.install")
    PrintTrace "$TRACE_DEBUG" "LCL_INSTALL_ITEMS = $LCL_INSTALL_ITEMS"
    local LCL_UNINSTALL_ITEMS
    LCL_UNINSTALL_ITEMS=$(echo $LCL_INSTRUCTIONS | jq -r ".$LCL_ITEM.uninstall")
    PrintTrace "$TRACE_DEBUG" "LCL_UNINSTALL_ITEMS = $LCL_UNINSTALL_ITEMS"
    local LCL_DESCRIPTIONS
    LCL_DESCRIPTIONS=$(echo $LCL_INSTRUCTIONS | jq -r ".$LCL_ITEM.descriptions")
    PrintTrace "$TRACE_DEBUG" "LCL_DESCRIPTIONS = $LCL_DESCRIPTIONS"

    if [ "$LCL_INSTALL_ITEMS" != "" ]; then
        INSTALL_ITEM_LIST=($(echo "$LCL_INSTALL_ITEMS" | jq -r 'keys_unsorted[]'))
        PrintTrace "$TRACE_INFO" "${ORG}[Installing $LCL_ITEM: ${INSTALL_ITEM_LIST[*]}]${NC}"
        for INSTALL_ITEM in "${INSTALL_ITEM_LIST[@]}"; do
            PrintTrace "$TRACE_DEBUG" "${ORG}$INSTALL_ITEM${NC}"
            INSTALL_STEPS=$(echo $LCL_INSTALL_ITEMS | jq -r ".\"$INSTALL_ITEM\"[]")
            PrintTrace "$TRACE_DEBUG" "${ORG}INSTALL_STEPS = $INSTALL_STEPS${NC}"
            CHECK_STEP=$(echo $LCL_CHECK_ITEMS | jq -r ".\"$INSTALL_ITEM\"[]")
            PrintTrace "$TRACE_DEBUG" "${ORG}CHECK_STEP = $CHECK_STEP${NC}"
            __installItem "$LCL_JSON_FILE_NAME" "$LCL_INSTALLED_TYPE" "$INSTALL_ITEM" "$CHECK_STEP" "$INSTALL_STEPS" "$LCL_UNINSTALL_ITEMS" "$LCL_DESCRIPTIONS" || PrintTrace "$TRACE_ERROR" "${RED}ERROR: $INSTALL_ITEM installation failed${NC}"
        done
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__createBinDirLink() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_CURRENT_DIR=$PWD
    local LCL_EXIT_CODE=0

    PrintTrace "$TRACE_DEBUG" "LCL_CURRENT_DIR = $LCL_CURRENT_DIR"
    if [ ! -d $HOME_BIN_DIR ]; then
        PrintTrace "$TRACE_INFO" "[Creating $HOME_BIN_DIR directory link to $LCL_CURRENT_DIR/$SH_BIN_DIR ...]"
        ln -s "$LCL_CURRENT_DIR/$SH_BIN_DIR" $HOME_BIN_DIR || LCL_EXIT_CODE=$?
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


#---------------------------
# main
#---------------------------
install_abkEnv_main() {
    local MAIN_ABK_LIB_FILE="./unixBin/abkLib.sh"
    local MAIN_DEFAULT_JSON_FILE="./tools_min.json"
    local MAIN_JSON_INSTALLED_COUNT=0
    local MAIN_EXIT_CODE=0
    local MAIN_JSON_FILES
    local MAIN_TOOLS_JSON_FILE
    local MAIN_TOOLS_JSON

    [ -f "$MAIN_ABK_LIB_FILE" ] && . "$MAIN_ABK_LIB_FILE" || PrintUsageAndExitWithCode 1 "${RED}ERROR: $MAIN_ABK_LIB_FILE could not be found.${NC}"
    # export TRACE_LEVEL=$TRACE_DEBUG
    export TRACE_LEVEL=$TRACE_INFO
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"

    PrintTrace "$TRACE_INFO" "   ABK_SHELL         = $ABK_SHELL"
    PrintTrace "$TRACE_INFO" "   BIN_DIR           = $BIN_DIR"
    PrintTrace "$TRACE_INFO" "   HOME_BIN_DIR      = $HOME_BIN_DIR"
    PrintTrace "$TRACE_INFO" "   SH_BIN_DIR        = $SH_BIN_DIR"
    PrintTrace "$TRACE_INFO" "   SH_PACKAGES_DIR   = $SH_PACKAGES_DIR"
    PrintTrace "$TRACE_INFO" "   ABK_ENV_FILE      = $ABK_ENV_FILE"
    PrintTrace "$TRACE_INFO" "   HOME              = $HOME"
    PrintTrace "$TRACE_INFO"

    # is parameter --help?
    [ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode "$ERROR_CODE_SUCCESS"

    AbkLib_CheckPreRequisites || PrintUsageAndExitWithCode "$ERROR_CODE_GENERAL_ERROR" "${RED}ERROR: cannot proceed Pre-Requisites are not met${NC}"

    # Is number of parameters ok
    if [ "$#" -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "No parameters provided, using default $MAIN_DEFAULT_JSON_FILE"
        MAIN_JSON_FILES=("$MAIN_DEFAULT_JSON_FILE")
    else
        MAIN_JSON_FILES=("$@")
    fi

    for MAIN_TOOLS_JSON_FILE in "${MAIN_JSON_FILES[@]}"; do

        # check if file exists
        [ ! -f "$MAIN_TOOLS_JSON_FILE" ] && PrintTrace "$TRACE_ERROR" "${ORG}WARNING: File could NOT be found: $MAIN_TOOLS_JSON_FILE${NC}" && continue
        # check if file is a JSON file
        [[ "$MAIN_TOOLS_JSON_FILE" != *.json ]] && PrintTrace "$TRACE_ERROR" "${ORG}WARNING: Skipping non-JSON file: $MAIN_TOOLS_JSON_FILE${NC}" && continue

        PrintTrace "$TRACE_INFO" "\n${BLU}Processing $MAIN_TOOLS_JSON_FILE${NC}"
        # get install json instructions
        __getJsonInstallInstructions MAIN_TOOLS_JSON "$MAIN_TOOLS_JSON_FILE" || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: Could not get correct install instructions from file: ${MAIN_TOOLS_JSON_FILE}${NC}"; continue;}
        PrintTrace "$TRACE_DEBUG" "MAIN_TOOLS_JSON = $MAIN_TOOLS_JSON"

        # check unix (MacOS/Linux version supported)
        AbkLib_CheckInstallationCompatibility "$MAIN_TOOLS_JSON" || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: The installation is not supported.${NC}"; continue; }
        __updatePackageManager "$MAIN_TOOLS_JSON" || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: __updatePackageManager failed${NC}"; continue; }

        # print description
        local LCL_DESCRIPTION
        LCL_DESCRIPTION=$(echo $MAIN_TOOLS_JSON | jq -r ".description")
        # shellcheck disable=SC2086
        PrintTrace "$TRACE_INFO" "${ORG}[$LCL_DESCRIPTION]${NC}"

        __createInstalledFile "$MAIN_TOOLS_JSON_FILE" || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: __createInstalledFile failed${NC}"; continue; }
        __installItemList "$MAIN_TOOLS_JSON_FILE" "$INSTALLED_TOOLS" "$MAIN_TOOLS_JSON" || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: __installItemList $INSTALLED_TOOLS failed${NC}"; continue; }
        __installItemList "$MAIN_TOOLS_JSON_FILE" "$INSTALLED_APPS" "$MAIN_TOOLS_JSON" || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: __installItemList $INSTALLED_APPS failed${NC}"; continue; }
        __installItemList "$MAIN_TOOLS_JSON_FILE" "$INSTALLED_FONTS" "$MAIN_TOOLS_JSON" || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: __installItemList $INSTALLED_FONTS failed${NC}"; continue; }

        ((MAIN_JSON_INSTALLED_COUNT++))
    done

    PrintTrace "$TRACE_DEBUG" "MAIN_JSON_INSTALLED_COUNT = $MAIN_JSON_INSTALLED_COUNT"
    if [ $MAIN_JSON_INSTALLED_COUNT -eq 0 ]; then
        # shellcheck disable=SC2086
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: No JSON files were processed${NC}"
        MAIN_EXIT_CODE=1
    else
        __createBinDirLink || PrintTrace "$TRACE_ERROR" "${RED}ERROR: __createBinDirLink failed with $?${NC}"
        __addAbkEnvToConfig "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || PrintUsageAndExitWithCode $? "${RED}ERROR: __addAbkEnvToConfig $HOME/$ABK_USER_CONFIG_FILE_SHELL failed${NC}"
        exec $ABK_SHELL
    fi

    # shellcheck disable=SC2086
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($MAIN_EXIT_CODE)"
    return $MAIN_EXIT_CODE
}

echo ""
echo "-> $0 ($*)"

# shellcheck disable=SC2068
install_abkEnv_main $@
LCL_EXIT_CODE=$?

echo "<- $0 (0)"
exit $LCL_EXIT_CODE
