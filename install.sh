#!/bin/bash


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode() {
    echo "$0 will create ABK environment"
    echo "the script $0 must be called without any parameters"
    echo "usage: $0"
    echo "  $0 --help           - display this info"
    echo
    echo -e $2
    echo "errorExitCode = $1"
    exit $1
}


__addAbkEnvToConfig() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
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

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (0)"
    return 0
}


__createInstalledFile() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_EXIT_CODE=0

    # ensure there is a directory to store the package information
    mkdir -p $INSTALLED_DIR || $LCL_EXIT_CODE=$?
    [ ! -f "$INSTALLED_DIR/$INSTALLED_FILE" ] && echo {} > $INSTALLED_DIR/$INSTALLED_FILE

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_RETURN_VAL)"
    return $LCL_RETURN_VAL
}


__updatePackageManager() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTRACTIONS=$1
    local LCL_EXIT_CODE=0

    # update brew / apt repository and packages
    local LCL_UPDATE_PACKAGES=$(echo $LCL_INSTRACTIONS | jq -r ".update_packages[]")
    if [ "$LCL_UPDATE_PACKAGES" != "" ]; then
        PrintTrace $TRACE_INFO "${ORG}[Updating packages]${NC}"
        while IFS= read -r LCL_UPDATE_PACKAGE; do
            PrintTrace $TRACE_DEBUG "${ORG}$LCL_UPDATE_PACKAGE${NC}"
            eval $LCL_UPDATE_PACKAGE
        done <<< "$LCL_UPDATE_PACKAGES"
    else
        PrintTrace $TRACE_CRITICAL "Did NOT find the update_packages section"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__installItem() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_ITEM=$1
    local LCL_INSTALL_INSTRACTIONS=$2
    local LCL_INSTALL_TYPE=$3
    local LCL_CHECK_INSTRACTIONS=$4
    local LCL_IS_APP_INSTALLED=1
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_DEBUG "LCL_ITEM                    = $LCL_ITEM"
    PrintTrace $TRACE_DEBUG "LCL_INSTALL_INSTRACTIONS    = $LCL_INSTALL_INSTRACTIONS"
    PrintTrace $TRACE_DEBUG "LCL_INSTALL_TYPE            = $LCL_INSTALL_TYPE"
    PrintTrace $TRACE_DEBUG "LCL_CHECK_INSTRACTIONS      = $LCL_CHECK_INSTRACTIONS"

    while IFS= read -r LCL_CHECK_STEP; do
        PrintTrace $TRACE_DEBUG "LCL_CHECK_STEP = $LCL_CHECK_STEP"
        EVAL_CHECK_STEP=$(eval $LCL_CHECK_STEP 2>/dev/null)
        PrintTrace $TRACE_DEBUG "EVAL_CHECK_STEP = $EVAL_CHECK_STEP"
        if [ "$EVAL_CHECK_STEP" != "" ]; then
            LCL_IS_APP_INSTALLED=0
        fi
        PrintTrace $TRACE_DEBUG "LCL_IS_APP_INSTALLED = $LCL_IS_APP_INSTALLED"
    done <<< "$LCL_CHECK_INSTRACTIONS"

    if [ $LCL_IS_APP_INSTALLED -eq 1 ]; then
        PrintTrace $TRACE_INFO "${YLW}[$LCL_ITEM installing ...]${NC}"
        local TOOL_INSTALLED=$TRUE

        while IFS= read -r INSTALL_STEP; do
            eval "$INSTALL_STEP" && AbkLib_MarkInstalledStep "$LCL_INSTALL_TYPE" "$LCL_ITEM" "$INSTALL_STEP"
        done <<< "$LCL_INSTALL_INSTRACTIONS"
    else
        PrintTrace $TRACE_INFO "${GRN}$LCL_ITEM already installed${NC}"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__installItemList() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTALLED_TYPE=$1
    local LCL_INSTRACTIONS=$2
    local LCL_EXIT_CODE=0
    local LCL_ITEM="${LCL_INSTALLED_TYPE//installed_/}"

   # install items
    local LCL_CHECK_ITEMS=$(echo $LCL_INSTRACTIONS | jq -r ".$LCL_ITEM.check")
    local LCL_INSTALL_ITEMS=$(echo $LCL_INSTRACTIONS | jq -r ".$LCL_ITEM.install")
    if [ "$LCL_INSTALL_ITEMS" != "" ]; then
        INSTALL_ITEM_LIST=($(echo "$LCL_INSTALL_ITEMS" | jq -r 'keys_unsorted[]'))
        PrintTrace $TRACE_INFO "${ORG}[Installing $LCL_ITEM: ${INSTALL_ITEM_LIST[@]}]${NC}"
        for INSTALL_ITEM in "${INSTALL_ITEM_LIST[@]}"; do
            PrintTrace $TRACE_DEBUG "${ORG}$INSTALL_ITEM${NC}"
            INSTALL_STEPS=$(echo $LCL_INSTALL_ITEMS | jq -r ".\"$INSTALL_ITEM\"[]")
            PrintTrace $TRACE_DEBUG "${ORG}INSTALL_STEPS = $INSTALL_STEPS${NC}"
            CHECK_STEP=$(echo $LCL_CHECK_ITEMS | jq -r ".\"$INSTALL_ITEM\"[]")
            PrintTrace $TRACE_DEBUG "${ORG}CHECK_STEP = $CHECK_STEP${NC}"
            __installItem "$INSTALL_ITEM" "$INSTALL_STEPS" "$LCL_INSTALLED_TYPE" "$CHECK_STEP" || PrintTrace $TRACE_ERROR "${RED}ERROR: $INSTALL_ITEM installation failed${NC}"
        done
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


__createBinDirLink() {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_CURRENT_DIR=$PWD
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_DEBUG "LCL_CURRENT_DIR = $LCL_CURRENT_DIR"
    if [ ! -d $HOME_BIN_DIR ]; then
        PrintTrace $TRACE_INFO "[Creating $HOME_BIN_DIR directory link to $LCL_CURRENT_DIR/$SH_BIN_DIR ...]"
        ln -s "$LCL_CURRENT_DIR/$SH_BIN_DIR" $HOME_BIN_DIR || LCL_EXIT_CODE=$?
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


#---------------------------
# main
#---------------------------
install_abkEnv_main() {
    local MAIN_ABK_LIB_FILE="./unixBin/abkLib.sh"
    local MAIN_TOOLS_JSON_FILE="./tools.json"
    local MAIN_ABK_INSTALL_OH_MY="__install_oh_my"
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

    # get install json instructions
    local MAIN_TOOLS_JSON=
    AbkLib_GetJsonInstructions MAIN_TOOLS_JSON "$MAIN_TOOLS_JSON_FILE" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} Could not get correct install instructions from file: ${MAIN_TOOLS_JSON_FILE[*]}"
    PrintTrace $TRACE_DEBUG "MAIN_TOOLS_JSON = $MAIN_TOOLS_JSON"

    # check unix (MacOS/Linux version supported)
    AbkLib_CheckInstallationCompability "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} The installation is not supported."

    __updatePackageManager "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __updatePackageManager failed"

    # print description
    local LCL_DESCRIPTION=$(echo $MAIN_TOOLS_JSON | jq -r ".description")
    PrintTrace $TRACE_INFO "${ORG}[$LCL_DESCRIPTION]${NC}"

    __createInstalledFile || PrintUsageAndExitWithCode $? "${RED}ERROR: __createInstalledFile failed${NC}"
    __installItemList "$INSTALLED_TOOLS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __installItemList $INSTALLED_TOOLS failed"
    __installItemList "$INSTALLED_APPS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __installItemList $INSTALLED_APPS failed"
    __installItemList "$INSTALLED_FONTS" "$MAIN_TOOLS_JSON" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __installItemList $INSTALLED_FONTS failed"

    __createBinDirLink || PrintTrace $TRACE_ERROR "${RED}ERROR:${NC} __createBinDirLink failed with $?"
    __addAbkEnvToConfig "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} __addAbkEnvToConfig $HOME/$ABK_USER_CONFIG_FILE_SHELL failed"

    AbkLib_SourceEnvironment "$HOME/$ABK_USER_CONFIG_FILE_SHELL" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_SourceEnvironment $HOME/$ABK_USER_CONFIG_FILE_SHELL failed"

    exec ${SHELL##*/}

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (0)"
    return 0
}

echo ""
echo "-> $0 ($@)"

install_abkEnv_main $@
LCL_EXIT_CODE=$?

echo "<- $0 (0)"
exit $LCL_EXIT_CODE
