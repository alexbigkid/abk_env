#!/bin/bash
# this script is collection of common function used in different scripts

# -----------------------------------------------------------------------------
# variables
# -----------------------------------------------------------------------------
export ABK_SHELL="${SHELL##*/}"
# echo "ABK_SHELL = $ABK_SHELL"
ABK_LIB_FILE_DIR=$(dirname "$BASH_SOURCE")
# echo "ABK_LIB_FILE_DIR = $ABK_LIB_FILE_DIR"
export ABK_ENV_FILE="${PWD}/${ABK_LIB_FILE_DIR}/env/abk.env"
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
export TRACE_LEVEL=$TRACE_DEBUG


#---------------------------
# variables
#---------------------------
export INSTALLED_DIR="unixPackages"
export INSTALLED_FILE="installed.json"
export INSTALLED_TOOLS="installed_tools"
export INSTALLED_APPS="installed_apps"
export INSTALLED_FONTS="installed_fonts"


# echo "pwd: $(pwd)"
# echo "\$0: $0"
# echo "basename: $(basename $0)"
# echo "dirname: $(dirname $0)"
# echo "dirname/readlink: $(dirname $(readlink -f $0))"

#---------------------------
# color definitions
#---------------------------
ABK_COLORS="$ABK_LIB_FILE_DIR/env/000_colors.env"
# shellcheck source=../env/000_colors.env
# echo "ABK_COLORS = $ABK_COLORS"
# shellcheck disable=SC1091
[ -f "$ABK_COLORS" ] && . "$ABK_COLORS" || echo -e "${RED}ERROR:${NC} colors definition file ($ABK_COLORS) could not be found"

#---------------------------
# vars definition
#---------------------------
ABK_VARS="$ABK_LIB_FILE_DIR/env/001_vars.env"
# echo "ABK_VARS = $ABK_VARS"
# shellcheck source=../env/001_vars.env
# shellcheck disable=SC1091
[ -f "$ABK_VARS" ] && . "$ABK_VARS" || echo -e "${RED}ERROR:${NC} vars definition file ($ABK_VARS) could not be found"

# -----------------------------------------------------------------------------
# internal variables definitions
# -----------------------------------------------------------------------------
# for here document to add to the profile
ABK_ENV_BEGIN="# BEGIN >>>>>> DO_NOT_REMOVE >>>>>>"
ABK_ENV_END="# END <<<<<< DO_NOT_REMOVE <<<<<<"
export ABK_ENV_NAME="ABK_ENV"

#---------------------------
# functions
#---------------------------
AbkLib_AddEnvironmentSettings() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV_NAME=$1
    local LCL_FILE_TO_ADD_CONTENT_TO=$2
    shift
    shift
    local LCL_SETTINGS_TO_ADD=("$@")
    local LCL_RESULT=$FALSE

    if [ "$LCL_ENV_NAME" != "" ] && [ -f "$LCL_FILE_TO_ADD_CONTENT_TO" ] && [ ${#LCL_SETTINGS_TO_ADD[@]} -ne 0 ]; then
        LCL_RESULT=$TRUE

        if grep -q -e "$ABK_ENV_BEGIN $LCL_ENV_NAME" "$LCL_FILE_TO_ADD_CONTENT_TO"; then
            PrintTrace $TRACE_INFO "    [Environment already added. Nothing to do here.]"
        else
            PrintTrace $TRACE_INFO "    [Adding $LCL_ENV_NAME environment ...]"
            cat >>"$LCL_FILE_TO_ADD_CONTENT_TO" <<-TEXT_TO_ADD
$ABK_ENV_BEGIN $LCL_ENV_NAME
$(printf "%s\n" "${LCL_SETTINGS_TO_ADD[@]}")
$ABK_ENV_END $LCL_ENV_NAME
TEXT_TO_ADD
        fi
    else
        PrintTrace $TRACE_CRITICAL "    ${RED}\tInvalid parameters passed in${NC}"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}

AbkLib_RemoveEnvironmentSettings() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV_NAME=$1
    local LCL_FILE_TO_REMOVE_CONTENT_FROM=$2
    local LCL_RESULT=$FALSE

    if [ -f "$LCL_FILE_TO_REMOVE_CONTENT_FROM" ]; then
        echo "   [File $LCL_FILE_TO_REMOVE_CONTENT_FROM exist ...]"
        LCL_RESULT=$TRUE
        if grep -q -e "$ABK_ENV_BEGIN $LCL_ENV_NAME" "$LCL_FILE_TO_REMOVE_CONTENT_FROM"; then
            PrintTrace $TRACE_INFO "   [ABK environment found removing it...]"
            sed -i -e "/^$ABK_ENV_BEGIN $LCL_ENV_NAME$/,/^$ABK_ENV_END $LCL_ENV_NAME$/d" "$LCL_FILE_TO_REMOVE_CONTENT_FROM"
        else
            PrintTrace $TRACE_INFO "   [ABK environment NOT found. Nothing to remove]"
        fi
    else
        echo "   [File: $LCL_FILE_TO_REMOVE_CONTENT_FROM does not exist.]"
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}

AbkLib_IsParameterHelp() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local NUMBER_OF_PARAMETERS=$1
    local PARAMETER=$2
    # shellcheck disable=SC2086
    if [ $NUMBER_OF_PARAMETERS -eq 1 ] && [ "$PARAMETER" == "--help" ]; then
        PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (TRUE)"
        return $TRUE
    else
        PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (FALSE)"
        return $FALSE
    fi
}

AbkLib_GetAbsolutePath() {
    local DIR_NAME
    DIR_NAME=$(dirname "$1")
    pushd "$DIR_NAME" >/dev/null || return
    local RESULT_PATH=$PWD
    popd >/dev/null || return
    echo "$RESULT_PATH"
}

AbkLib_GetPathFromLink() {
    local RESULT_PATH
    # shellcheck disable=SC2046
    RESULT_PATH=$(dirname $([ -L "$1" ] && readlink -n "$1"))
    # shellcheck disable=SC2086
    echo $RESULT_PATH
}

AbkLib_IsStringInArray() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
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

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}($LCL_MATCH_FOUND)"
    return $LCL_MATCH_FOUND
}

AbkLib_IsBrewInstalled() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RESULT=$TRUE
    # homebrew installed?
    if [[ $(command -v brew) == "" ]]; then
        LCL_RESULT=$FALSE
        echo "WARNING: Homebrew is not installed, please install with:"
        echo "/usr/bin/ruby -e \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\""
    fi
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}


AbkLib_CheckNumberOfParameters() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_EXPECTED_NUMBER_OF_PARAMS=$1
    shift
    local LCL_PARAMETERS_PASSED_IN=("$@")

    # shellcheck disable=SC2086
    if [ $LCL_EXPECTED_NUMBER_OF_PARAMS -ne ${#LCL_PARAMETERS_PASSED_IN[@]} ]; then
        PrintTrace $TRACE_CRITICAL "${RED}ERROR: invalid number of parameters.${NC}"
        PrintTrace $TRACE_INFO "\texpected number:\t$LCL_EXPECTED_NUMBER_OF_PARAMS"
        PrintTrace $TRACE_INFO "\tpassed in number:\t${#LCL_PARAMETERS_PASSED_IN[@]}"
        PrintTrace $TRACE_INFO "\tparameters passed in:\t${LCL_PARAMETERS_PASSED_IN[*]}"
        PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (FALSE)"
        return $FALSE
    else
        PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} (TRUE)"
        return $TRUE
    fi
}

AbkLib_GetIdLike_linux() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_ID_LIKE
    AbkLib_GetId_linux LCL_LINUX_ID_LIKE || PrintTrace $TRACE_ERROR "AbkLib_GetId_linux LCL_LINUX_ID_LIKE failed"
    if [ "$LCL_LINUX_ID_LIKE" == "" ] || [ "$LCL_LINUX_ID_LIKE" != "debian" ]; then
        # shellcheck disable=SC2002
        LCL_LINUX_ID_LIKE="$(cat /etc/os-release | grep '^ID_LIKE=.*' | cut -d'=' -f2)"
    fi
    PrintTrace $TRACE_DEBUG "    LCL_LINUX_ID_LIKE = $LCL_LINUX_ID_LIKE"
    [ "$LCL_LINUX_ID_LIKE" == "" ] && LCL_EXIT_CODE=1

    eval "$LCL_RETURN_VAR"=\$LCL_LINUX_ID_LIKE
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_ID_LIKE)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_linux() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_ID
    # shellcheck disable=SC2002
    LCL_LINUX_ID="$(cat /etc/os-release | grep '^ID=.*' | cut -d'=' -f2)"
    [ "$LCL_LINUX_ID" == "" ] && LCL_EXIT_CODE=1
    PrintTrace $TRACE_DEBUG "    LCL_LINUX_ID = $LCL_LINUX_ID"

    eval "$LCL_RETURN_VAR"=\$LCL_LINUX_ID
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_macOS() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_MACOS_ID="macOS"
    # local LCL_MACOS_ID="$(sw_vers -ProductName)" # that not always gives MacOS
    # [ "$LCL_MACOS_ID" == "" ] && LCL_EXIT_CODE=1 # not needed because it is hard coded now
    PrintTrace $TRACE_DEBUG "    LCL_MACOS_ID = $LCL_MACOS_ID"

    eval "$LCL_RETURN_VAR"=\$LCL_MACOS_ID
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_MACOS_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_unix() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_UNIX_ID=
    AbkLib_GetId_"$ABK_UNIX_TYPE" LCL_UNIX_ID || LCL_EXIT_CODE=$?

    eval "$LCL_RETURN_VAR"=\$LCL_UNIX_ID
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_UNIX_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_linux() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_VERSION_ID
    # shellcheck disable=SC2002
    LCL_LINUX_VERSION_ID="$(cat /etc/os-release | grep '^VERSION_ID=.*' | cut -d'=' -f2 | sed 's/"//g')"
    PrintTrace $TRACE_DEBUG "    LCL_LINUX_VERSION_ID = $LCL_LINUX_VERSION_ID"
    [ "$LCL_LINUX_VERSION_ID" == "" ] && LCL_EXIT_CODE=1

    eval "$LCL_RETURN_VAR"=\$LCL_LINUX_VERSION_ID
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_macOS() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_MACOS_VERSION_ID
    LCL_MACOS_VERSION_ID="$(sw_vers -productVersion | cut -d'.' -f1)"
    PrintTrace $TRACE_DEBUG "    LCL_MACOS_VERSION_ID = $LCL_MACOS_VERSION_ID"
    [ "$LCL_MACOS_VERSION_ID" == "" ] && LCL_EXIT_CODE=1

    eval "$LCL_RETURN_VAR"=\$LCL_MACOS_VERSION_ID
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_MACOS_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_unix() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_UNIX_VERSION_ID=
    AbkLib_GetVersionId_"$ABK_UNIX_TYPE" LCL_UNIX_VERSION_ID || LCL_EXIT_CODE=$?

    eval "$LCL_RETURN_VAR"=\$LCL_UNIX_VERSION_ID
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_UNIX_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_CheckPreRequisites_macOS() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0
    local IS_BREW_INSTALLED=$FALSE

    [ "$(command -v brew)" != "" ] && IS_BREW_INSTALLED=$TRUE
    PrintTrace $TRACE_DEBUG "    IS_BREW_INSTALLED = $IS_BREW_INSTALLED"
    if [ "$IS_BREW_INSTALLED" == "$FALSE" ]; then
        # shellcheck disable=SC2016
        PrintTrace $TRACE_INFO '    ERROR: Brew is NOT installed. Please install with: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        PrintTrace $TRACE_INFO '    For details please see: https://brew.sh/'
        LCL_EXIT_CODE=1
    else
        # check jq is installed, we need it to read json tool installation instructions file
        if ! command -v jq >/dev/null 2>&1; then
            brew install jq || LCL_EXIT_CODE=$?
        fi
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckPreRequisites_linux() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0

    AbkLib_GetIdLike_linux LINUX_ID_LIKE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetIdLike_linux failed"
    PrintTrace $TRACE_DEBUG "    LINUX_ID_LIKE = $LINUX_ID_LIKE"
    AbkLib_IsStringInArray "$LINUX_ID_LIKE" "${ABK_SUPPORTED_LINUX_ID_LIKE[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $LINUX_ID_LIKE is not supported.\nSupported Linux ID likes are: ${ABK_SUPPORTED_LINUX_ID_LIKE[*]}"

    # check jq is installed, we need it to read json tool installation instructions file
    if ! command -v jq >/dev/null 2>&1; then
        sudo apt install -y jq || LCL_EXIT_CODE=$?
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckPreRequisites() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0

    # is $SHELL supported
    PrintTrace $TRACE_DEBUG "    ABK_SHELL = $ABK_SHELL"
    AbkLib_IsStringInArray "$ABK_SHELL" "${ABK_SUPPORTED_SHELLS[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $ABK_SHELL is not supported.\nPlease consider using one of those shells: ${ABK_SUPPORTED_SHELLS[*]}"

    # get unix type
    PrintTrace $TRACE_DEBUG "    ABK_UNIX_TYPE = $ABK_UNIX_TYPE"
    AbkLib_IsStringInArray "$ABK_UNIX_TYPE" "${ABK_SUPPORTED_UNIX[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $ABK_UNIX_TYPE is not supported.\nSupported Unix types are: ${ABK_SUPPORTED_UNIX[*]}"

    AbkLib_CheckPreRequisites_"$ABK_UNIX_TYPE" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} PreRequisites for ${ABK_UNIX_TYPE} are not met"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_WriteUninstallSteps() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} (hidden)"
    # PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} ($*)"
    local LCL_JSON_FILE_NAME_BACKUP=$1
    local LCL_INSTALLED_TYPE=$2
    local LCL_INSTALLED_TOOL=$3
    local LCL_UNINSTALLED_STEPS=$4
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_DEBUG "    LCL_JSON_FILE_NAME_BACKUP = $LCL_JSON_FILE_NAME_BACKUP"
    PrintTrace $TRACE_DEBUG "    LCL_INSTALLED_TYPE        = $LCL_INSTALLED_TYPE"
    PrintTrace $TRACE_DEBUG "    LCL_INSTALLED_TOOL        = $LCL_INSTALLED_TOOL"
    PrintTrace $TRACE_DEBUG "    LCL_UNINSTALLED_STEPS     = $LCL_UNINSTALLED_STEPS"

    # Extract uninstall steps for this tool
    local LCL_UNINSTALLATION
    LCL_UNINSTALLATION=$(jq -r --arg tool "$LCL_INSTALLED_TOOL" '.[$tool]' <<< "$LCL_UNINSTALLED_STEPS")

    # Make sure it's not null
    if [[ "$LCL_UNINSTALLATION" == "null" || -z "$LCL_UNINSTALLATION" ]]; then
        PrintTrace $TRACE_DEBUG "    No uninstall steps found for tool: $LCL_INSTALLED_TOOL"
        return 1
    fi

    # Write uninstall steps into the JSON backup file
    jq --arg type "$LCL_INSTALLED_TYPE" \
       --arg tool "$LCL_INSTALLED_TOOL" \
       --argjson steps "$LCL_UNINSTALLATION" \
       '(.[$type] //= {}) | .[$type][$tool] = $steps' \
       "$INSTALLED_DIR/$LCL_JSON_FILE_NAME_BACKUP" > "$INSTALLED_DIR/$LCL_JSON_FILE_NAME_BACKUP.tmp" \
    && mv "$INSTALLED_DIR/$LCL_JSON_FILE_NAME_BACKUP.tmp" "$INSTALLED_DIR/$LCL_JSON_FILE_NAME_BACKUP" \
    && PrintTrace $TRACE_DEBUG "    Uninstall steps written successfully."

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckInstallationCompatibility() {
    PrintTrace $TRACE_FUNCTION "\n-> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTRUCTIONS=$1
    local LCL_EXIT_CODE=0
    local CHECK_UNIX_ID=
    local CHECK_UNIX_VERSION_ID=

    AbkLib_GetId_unix CHECK_UNIX_ID || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetId_unix failed"
    AbkLib_GetVersionId_unix CHECK_UNIX_VERSION_ID || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetVersionId_unix failed"
    PrintTrace $TRACE_DEBUG "    CHECK_UNIX_ID               = $CHECK_UNIX_ID"
    PrintTrace $TRACE_DEBUG "    CHECK_UNIX_VERSION_ID       = $CHECK_UNIX_VERSION_ID"

    # check distro name support
    local LCL_MATCH_SUPPORTED_VERSION
    LCL_MATCH_SUPPORTED_VERSION=$(echo "$LCL_INSTRUCTIONS" | jq -r ".supported_versions.${CHECK_UNIX_ID}[] | select(.==\"${CHECK_UNIX_VERSION_ID}\")")
    PrintTrace $TRACE_DEBUG "    LCL_MATCH_SUPPORTED_VERSION = $LCL_MATCH_SUPPORTED_VERSION"
    # shellcheck disable=SC2319
    [ "$LCL_MATCH_SUPPORTED_VERSION" == "" ] && PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} UnixId: $CHECK_UNIX_ID with version: $CHECK_UNIX_VERSION_ID is not supported.\nSupported Unix types are: $(echo "$LCL_INSTRUCTIONS" | jq -r '.supported_versions')"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# PrintTrace() {
#     local LCL_TRACE_LEVEL=$1
#     shift
#     local LCL_PRINT_STRING=("$@")
#     if [ "$LCL_TRACE_LEVEL" -eq "$TRACE_FUNCTION" ]; then
#         [ "$TRACE_LEVEL" -ge "$LCL_TRACE_LEVEL" ] && echo -e "${CYN}${LCL_PRINT_STRING[*]}${NC}"
#     else
#         [ "$TRACE_LEVEL" -ge "$LCL_TRACE_LEVEL" ] && echo -e "${LCL_PRINT_STRING[@]}"
#     fi
# }
