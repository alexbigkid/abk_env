#!/bin/bash
# this script is collection of common function used in different scripts

# -----------------------------------------------------------------------------
# variables
# -----------------------------------------------------------------------------
ABK_LIB_FILE_DIR=$(dirname "$BASH_SOURCE")
# echo "ABK_LIB_FILE_DIR = $ABK_LIB_FILE_DIR"
ABK_ENV_FILE="$PWD/$ABK_LIB_FILE_DIR/env/abk.env"
# echo "ABK_ENV_FILE = $ABK_ENV_FILE"
export TRUE=0
export FALSE=1

export TRACE_NONE=0
export TRACE_CRITICAL=1
export TRACE_ERROR=2
export TRACE_FUNCTION=3
export TRACE_INFO=4
export TRACE_DEBUG=5
export TRACE_ALL=6

#---------------------------
# variables
#---------------------------
INSTALLED_DIR="unixPackages"
INSTALLED_FILE="installed.json"
INSTALLED_TOOLS="installed_tools"
INSTALLED_APPS="installed_apps"
INSTALLED_FONTS="installed_fonts"


# echo "pwd: $(pwd)"
# echo "\$0: $0"
# echo "basename: $(basename $0)"
# echo "dirname: $(dirname $0)"
# echo "dirname/readlink: $(dirname $(readlink -f $0))"

#---------------------------
# vars definition
#---------------------------
ABK_VARS="$ABK_LIB_FILE_DIR/env/000_vars.env"
# echo "ABK_VARS = $ABK_VARS"
[ -f "$ABK_VARS" ] && . $ABK_VARS || echo -e "${RED}ERROR:${NC} vars definition file ($ABK_VARS) could not be found"

#---------------------------
# color definitions
#---------------------------
LCL_ABK_COLORS="$ABK_LIB_FILE_DIR/env/001_colors.env"
# echo "LCL_ABK_COLORS = $LCL_ABK_COLORS"
[ -f "$LCL_ABK_COLORS" ] && . $LCL_ABK_COLORS || echo -e "${RED}ERROR:${NC} colors definition file ($LCL_ABK_COLORS) could not be found"

# -----------------------------------------------------------------------------
# internal variables definitions
# -----------------------------------------------------------------------------
# for here document to add to the profile
ABK_ENV_BEGIN="# BEGIN >>>>>> DO_NOT_REMOVE >>>>>>"
ABK_ENV_END="# END <<<<<< DO_NOT_REMOVE <<<<<<"
ABK_ENV_NAME="ABK_ENV"

#---------------------------
# functions
#---------------------------
AbkLib_AddEnvironmentSettings() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_ENV_NAME=$1
    local LCL_FILE_TO_ADD_CONTENT_TO=$2
    shift
    shift
    local LCL_SETTINGS_TO_ADD=("$@")
    local LCL_RESULT=$FALSE

    if [ "$LCL_ENV_NAME" != "" ] && [ -f "$LCL_FILE_TO_ADD_CONTENT_TO" ] && [ ${#LCL_SETTINGS_TO_ADD[@]} -ne 0 ]; then
        LCL_RESULT=$TRUE

        if grep -q -e "$IROBOT_ENV_BEGIN $LCL_ENV_NAME" $LCL_FILE_TO_ADD_CONTENT_TO; then
            PrintTrace $TRACE_INFO "    [Environment already added. Nothing to do here.]"
        else
            PrintTrace $TRACE_INFO "    [Adding $LCL_ENV_NAME environment ...]"
            cat >>$LCL_FILE_TO_ADD_CONTENT_TO <<-TEXT_TO_ADD
$ABK_ENV_BEGIN $LCL_ENV_NAME
$(printf "%s\n" "${LCL_SETTINGS_TO_ADD[@]}")
$ABK_ENV_END $LCL_ENV_NAME
TEXT_TO_ADD
        fi
    else
        PrintTrace $TRACE_CRITICAL "    ${RED}\tInvalid parameters passed in${NC}"
    fi

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}

AbkLib_RemoveEnvironmentSettings() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_ENV_NAME=$1
    local LCL_FILE_TO_REMOVE_CONTENT_FROM=$2
    local LCL_RESULT=$FALSE

    if [ -f "$LCL_FILE_TO_REMOVE_CONTENT_FROM" ]; then
        echo "   [File $LCL_FILE_TO_REMOVE_CONTENT_FROM exist ...]"
        LCL_RESULT=$TRUE
        if grep -q -e "$ABK_ENV_BEGIN $LCL_ENV_NAME" $LCL_FILE_TO_REMOVE_CONTENT_FROM; then
            PrintTrace $TRACE_INFO "   [ABK environment found removing it...]"
            sed -i -e "/^$ABK_ENV_BEGIN $LCL_ENV_NAME$/,/^$ABK_ENV_END $LCL_ENV_NAME$/d" "$LCL_FILE_TO_REMOVE_CONTENT_FROM"
        else
            PrintTrace $TRACE_INFO "   [ABK environment NOT found. Nothng to remove]"
        fi
    else
        echo "   [File: $LCL_FILE_TO_REMOVE_CONTENT_FROM does not exist.]"
    fi

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}

AbkLib_IsParameterHelp() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local NUMBER_OF_PARAMETERS=$1
    local PARAMETER=$2
    if [ $NUMBER_OF_PARAMETERS -eq 1 ] && [ "$PARAMETER" == "--help" ]; then
        PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (TRUE)"
        return $TRUE
    else
        PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (FALSE)"
        return $FALSE
    fi
}

AbkLib_GetAbsolutePath() {
    local DIR_NAME=$(dirname "$1")
    pushd "$DIR_NAME" >/dev/null
    local RESULT_PATH=$PWD
    popd >/dev/null
    echo $RESULT_PATH
}

AbkLib_GetPathFromLink() {
    local RESULT_PATH=$(dirname $([ -L "$1" ] && readlink -n "$1"))
    echo $RESULT_PATH
}

AbkLib_IsStringInArray() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_STRING_TO_SEARCH_FOR=$1
    shift
    local LCL_ARRAY_TO_SEARCH_IN=("$@")
    local LCL_MATCH_FOUND=$FALSE

    for element in "${LCL_ARRAY_TO_SEARCH_IN[@]}"; do
        if [ "$LCL_STRING_TO_SEARCH_FOR" = "$element" ]; then
            LCL_MATCH_FOUND=$TRUE
            break
        fi
    done

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_MATCH_FOUND)"
    return $LCL_MATCH_FOUND
}

AbkLib_IsBrewInstalled() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RESULT=$TRUE
    # homebrew installed?
    if [[ $(command -v brew) == "" ]]; then
        LCL_RESULT=$FALSE
        echo "WARNING: Hombrew is not installed, please install with:"
        echo "/usr/bin/ruby -e \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\""
    fi
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}


AbkLib_SourceEnvironment() {
    local LCL_USER_CONFIG_FILE_SHELL=$1
    # todo: find a way to re-fresh environment from the shell script. As of now it does not work for zsh
    # source $LCL_USER_CONFIG_FILE_SHELL
}


AbkLib_CheckNumberOfParameters() {
    PrintTrace $TRACE_FUNCTION "\n    -> ${FUNCNAME[0]} ($*)"
    local LCL_EXPECTED_NUMBER_OF_PARAMS=$1
    shift
    local LCL_PARAMETERS_PASSED_IN=("$@")

    if [ $LCL_EXPECTED_NUMBER_OF_PARAMS -ne ${#LCL_PARAMETERS_PASSED_IN[@]} ]; then
        PrintTrace $TRACE_CRITICAL "${RED}ERROR: invalid number of parameters.${NC}"
        PrintTrace $TRACE_INFO "\texpected number:\t$LCL_EXPECTED_NUMBER_OF_PARAMS"
        PrintTrace $TRACE_INFO "\tpassed in number:\t${#LCL_PARAMETERS_PASSED_IN[@]}"
        PrintTrace $TRACE_INFO "\tparameters passed in:\t${LCL_PARAMETERS_PASSED_IN[@]}"
        PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (FALSE)"
        return $FALSE
    else
        PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (TRUE)"
        return $TRUE
    fi
}

AbkLib_GetIdLike_linux() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_ID_LIKE=
    AbkLib_GetId_linux LCL_LINUX_ID_LIKE || PrintTrace $TRACE_ERROR "AbkLib_GetId_linux LCL_LINUX_ID_LIKE failed"
    if [ "$LCL_LINUX_ID_LIKE" == "" ] || [ "$LCL_LINUX_ID_LIKE" != "debian" ]; then
        LCL_LINUX_ID_LIKE="$(cat /etc/os-release | grep '^ID_LIKE=.*' | cut -d'=' -f2)"
    fi
    PrintTrace $TRACE_DEBUG "    LCL_LINUX_ID_LIKE = $LCL_LINUX_ID_LIKE"
    [ "$LCL_LINUX_ID_LIKE" == "" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_LINUX_ID_LIKE
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_ID_LIKE)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_linux() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_ID="$(cat /etc/os-release | grep '^ID=.*' | cut -d'=' -f2)"
    [ "$LCL_LINUX_ID" == "" ] && LCL_EXIT_CODE=1
    PrintTrace $TRACE_DEBUG "    LCL_LINUX_ID = $LCL_LINUX_ID"

    eval $LCL_RETURN_VAR=\$LCL_LINUX_ID
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_macOS() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_MACOS_ID="macOS"
    # local LCL_MACOS_ID="$(sw_vers -ProductName)" # that not always gives MacOS
    # [ "$LCL_MACOS_ID" == "" ] && LCL_EXIT_CODE=1 # not needed because it is hard coded now
    PrintTrace $TRACE_DEBUG "    LCL_MACOS_ID = $LCL_MACOS_ID"

    eval $LCL_RETURN_VAR=\$LCL_MACOS_ID
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_MACOS_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_unix() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_UNIX_ID=
    AbkLib_GetId_$ABK_UNIX_TYPE LCL_UNIX_ID || LCL_EXIT_CODE=$?

    eval $LCL_RETURN_VAR=\$LCL_UNIX_ID
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_UNIX_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_linux() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_VERSION_ID="$(cat /etc/os-release | grep '^VERSION_ID=.*' | cut -d'=' -f2 | sed 's/"//g')"
    PrintTrace $TRACE_DEBUG "    LCL_LINUX_VERSION_ID = $LCL_LINUX_VERSION_ID"
    [ "$LCL_LINUX_VERSION_ID" == "" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_LINUX_VERSION_ID
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_macOS() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_MACOS_VERSION_ID="$(sw_vers -productVersion | cut -d'.' -f1)"
    PrintTrace $TRACE_DEBUG "    LCL_MACOS_VERSION_ID = $LCL_MACOS_VERSION_ID"
    [ "$LCL_MACOS_VERSION_ID" == "" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_MACOS_VERSION_ID
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_MACOS_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_unix() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_UNIX_VERSION_ID=
    AbkLib_GetVersionId_$ABK_UNIX_TYPE LCL_UNIX_VERSION_ID || LCL_EXIT_CODE=$?

    eval $LCL_RETURN_VAR=\$LCL_UNIX_VERSION_ID
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_UNIX_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetJsonInstructions() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_JSON_FILE=$2
    local LCL_EXIT_CODE=0
    local LCL_JSON_KEY=".$ABK_UNIX_TYPE"
    local LCL_JSON=$(cat $LCL_JSON_FILE)
    # PrintTrace $TRACE_DEBUG "LCL_JSON = $LCL_JSON"

    if [ "$ABK_UNIX_TYPE" == "linux" ]; then
        AbkLib_GetIdLike_linux LINUX_ID_LIKE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetIdLike_linux failed"
        LCL_JSON_KEY="${LCL_JSON_KEY}.$LINUX_ID_LIKE"
    fi

    local LCL_OS_INSTRACTIONS=$(echo "$LCL_JSON" | jq -r "$LCL_JSON_KEY")
    # PrintTrace $TRACE_DEBUG "    LCL_OS_INSTRACTIONS = $LCL_OS_INSTRACTIONS"

    eval $LCL_RETURN_VAR=\$LCL_OS_INSTRACTIONS
    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}

AbkLib_CheckPreRequisites_macOS() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0
    local IS_BREW_INSTALLED=$FALSE

    [ "$(command -v brew)" != "" ] && IS_BREW_INSTALLED=$TRUE
    PrintTrace $TRACE_DEBUG "    IS_BREW_INSTALLED = $IS_BREW_INSTALLED"
    if [ "$IS_BREW_INSTALLED" == "$FALSE" ]; then
        PrintTrace $TRACE_INFO '    ERROR: Brew is NOT installed. Please install with: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        PrintTrace $TRACE_INFO '    For details please see: https://brew.sh/'
        LCL_EXIT_CODE=1
    else
        # check jq is installed, we need it to read json tool installation instructions file
        local LCL_JQ='jq'
        local LCL_JQ_INSTALLATION="brew install $LCL_JQ"
        AbkLib_InstallTool "$LCL_JQ" "$LCL_JQ_INSTALLATION" || PrintUsageAndExitWithCode $? "${RED}ERROR: $LCL_JQ installation failed${NC}"
    fi

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckPreRequisites_linux() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0

    AbkLib_GetIdLike_linux LINUX_ID_LIKE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetIdLike_linux failed"
    PrintTrace $TRACE_DEBUG "    LINUX_ID_LIKE = $LINUX_ID_LIKE"
    AbkLib_IsStringInArray $LINUX_ID_LIKE "${ABK_SUPPORTED_LINUX_ID_LIKE[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $LINUX_ID_LIKE is not supported.\nSupported Linux ID likes are: ${ABK_SUPPORTED_LINUX_ID_LIKE[*]}"

    # check jq is installed, we need it to read json tool installation instructions file
    local LCL_JQ='jq'
    local LCL_JQ_INSTALLATION="sudo apt install -y $LCL_JQ"
    AbkLib_InstallTool "$LCL_JQ" "$LCL_JQ_INSTALLATION" || PrintUsageAndExitWithCode $? "${RED}ERROR: $LCL_JQ installation failed${NC}"

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckPreRequisites() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0

    # is $SHELL supported
    PrintTrace $TRACE_DEBUG "    ABK_SHELL = $ABK_SHELL"
    AbkLib_IsStringInArray $ABK_SHELL "${ABK_SUPPORTED_SHELLS[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $ABK_SHELL is not supported.\nPlease consider using one of those shells: ${ABK_SUPPORTED_SHELLS[*]}"

    # get unix type
    PrintTrace $TRACE_DEBUG "    ABK_UNIX_TYPE = $ABK_UNIX_TYPE"
    AbkLib_IsStringInArray $ABK_UNIX_TYPE "${ABK_SUPPORTED_UNIX[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $ABK_UNIX_TYPE is not supported.\nSupported Unix types are: ${ABK_SUPPORTED_UNIX[*]}"

    AbkLib_CheckPreRequisites_$ABK_UNIX_TYPE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} PreRequisites for ${ABK_UNIX_TYPE} are not met"

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_MarkInstalledStep() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_INSTALLED_TYPE=$1
    local LCL_INSTALLED_TOOL=$2
    local LCL_INSTALLED_STEP=$3
    local LCL_EXIT_CODE=0

    local LCL_INSTALLATION_LINE=$(jq --arg type "$LCL_INSTALLED_TYPE" --arg app "$LCL_INSTALLED_TOOL" '.[$type][$app]' "$INSTALLED_DIR/$INSTALLED_FILE" | grep "$LCL_INSTALLED_STEP")
    PrintTrace $TRACE_DEBUG "    LCL_INSTALLATION_LINE =$LCL_INSTALLATION_LINE"
    if [ "$LCL_INSTALLATION_LINE" == "" ]; then
        # If it doesn't exist, add the line to the JSON file
        jq --arg type "$LCL_INSTALLED_TYPE" --arg app "$LCL_INSTALLED_TOOL" --arg step "$LCL_INSTALLED_STEP" \
            '.[$type][$app] += [$step]' "$INSTALLED_DIR/$INSTALLED_FILE" > "$INSTALLED_DIR/$INSTALLED_FILE.tmp" \
            && mv "$INSTALLED_DIR/$INSTALLED_FILE.tmp" "$INSTALLED_DIR/$INSTALLED_FILE"
        [ $? -eq 0 ] && PrintTrace $TRACE_DEBUG "    Line added successfully."
    else
        PrintTrace $TRACE_DEBUG "    Line already exists. Skipped adding."
    fi

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_InstallTool() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($*)"
    local LCL_TOOL=$1
    local LCL_INSTALL_INSTRACTIONS=$2
    local LCL_EXIT_CODE=0

    if [ "$(command -v $LCL_TOOL)" = "" ]; then
        PrintTrace $TRACE_INFO "    ${YLW}[$LCL_TOOL installation ...]${NC}"
        local TOOL_INSTALLED=$TRUE

        while IFS= read -r INSTALL_STEP; do
            PrintTrace $TRACE_INFO "    installation step: ${YLW}$INSTALL_STEP${NC}"
            eval "$INSTALL_STEP" && AbkLib_MarkInstalledStep "$INSTALLED_TOOLS" "$LCL_TOOL" "$INSTALL_STEP"
        done <<< "$LCL_INSTALL_INSTRACTIONS"
    else
        PrintTrace $TRACE_INFO "    ${GRN}$LCL_TOOL already installed${NC}"
    fi

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckInstallationCompability() {
    PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTRACTIONS=$1
    local LCL_EXIT_CODE=0
    local CHECK_UNIX_ID=
    local CHECK_UNIX_VERSION_ID=

    AbkLib_GetId_unix CHECK_UNIX_ID || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetId_unix failed"
    AbkLib_GetVersionId_unix CHECK_UNIX_VERSION_ID || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetVersionId_unix failed"
    PrintTrace $TRACE_DEBUG "    CHECK_UNIX_ID               = $CHECK_UNIX_ID"
    PrintTrace $TRACE_DEBUG "    CHECK_UNIX_VERSION_ID       = $CHECK_UNIX_VERSION_ID"

    # check distro name support
    local LCL_MATCH_SUPPORTED_VERSION=$(echo $LCL_INSTRACTIONS | jq -r ".supported_versions.$CHECK_UNIX_ID[] | select(.==\"$CHECK_UNIX_VERSION_ID\")")
    PrintTrace $TRACE_DEBUG "    LCL_MATCH_SUPPORTED_VERSION = $LCL_MATCH_SUPPORTED_VERSION"
    [ "$LCL_MATCH_SUPPORTED_VERSION" == "" ] && PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} UnixId: $CHECK_UNIX_ID with version: $CHECK_UNIX_VERSION_ID is not supported.\nSupported Unix types are: $(echo $LCL_INSTRACTIONS | jq -r ".supported_versions")"

    PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}

PrintTrace() {
    local LCL_TRACE_LEVEL=$1
    shift
    local LCL_PRINT_STRING=("$@")
    if [ "$LCL_TRACE_LEVEL" -eq "$TRACE_FUNCTION" ]; then
        [ "$TRACE_LEVEL" -ge "$LCL_TRACE_LEVEL" ] && echo -e "${CYAN}${LCL_PRINT_STRING[@]}${NC}"
    else
        [ "$TRACE_LEVEL" -ge "$LCL_TRACE_LEVEL" ] && echo -e "${LCL_PRINT_STRING[@]}"
    fi
}
