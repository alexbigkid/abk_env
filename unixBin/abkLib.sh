#!/bin/bash
# this script is collection of common function used in different scripts

# -----------------------------------------------------------------------------
# variables
# -----------------------------------------------------------------------------
export TRUE=0
export FALSE=1

ABK_LIB_FILE_DIR=$(dirname "$BASH_SOURCE")
# echo "ABK_LIB_FILE_DIR = $ABK_LIB_FILE_DIR"
ABK_ENV_FILE="$PWD/$ABK_LIB_FILE_DIR/env/abk.env"
# echo "ABK_ENV_FILE = $ABK_ENV_FILE"

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
[ -f "$ABK_VARS" ] && . $ABK_VARS || echo "ERROR: vars definition file ($ABK_VARS) could not be found"

#---------------------------
# color definitions
#---------------------------
LCL_ABK_COLORS="$ABK_LIB_FILE_DIR/env/001_colors.env"
# echo "LCL_ABK_COLORS = $LCL_ABK_COLORS"
[ -f "$LCL_ABK_COLORS" ] && . $LCL_ABK_COLORS || echo "ERROR: colors definition file ($LCL_ABK_COLORS) could not be found"

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
AbkLib_PrintTrace() {
    local LCL_TRACE_LEVEL=$1
    shift
    local LCL_PRINT_STRING=("$@")
    if [ "$LCL_TRACE_LEVEL" -eq "$TRACE_FUNCTION" ]; then
        [ "$TRACE_LEVEL" -ge "$LCL_TRACE_LEVEL" ] && echo -e "${CYAN}${LCL_PRINT_STRING[@]}${NC}"
    else
        [ "$TRACE_LEVEL" -ge "$LCL_TRACE_LEVEL" ] && echo -e "${LCL_PRINT_STRING[@]}"
    fi
}

AbkLib_AddEnvironmentSettings() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_ENV_NAME=$1
    local LCL_FILE_TO_ADD_CONTENT_TO=$2
    shift
    shift
    local LCL_SETTINGS_TO_ADD=("$@")
    local LCL_RESULT=$FALSE

    if [ "$LCL_ENV_NAME" != "" ] && [ -f "$LCL_FILE_TO_ADD_CONTENT_TO" ] && [ ${#LCL_SETTINGS_TO_ADD[@]} -ne 0 ]; then
        LCL_RESULT=$TRUE

        if grep -q -e "$IROBOT_ENV_BEGIN $LCL_ENV_NAME" $LCL_FILE_TO_ADD_CONTENT_TO; then
            AbkLib_PrintTrace $TRACE_INFO "    [Environment already added. Nothing to do here.]"
        else
            AbkLib_PrintTrace $TRACE_INFO "    [Adding $LCL_ENV_NAME environment ...]"
            cat >>$LCL_FILE_TO_ADD_CONTENT_TO <<-TEXT_TO_ADD
$ABK_ENV_BEGIN $LCL_ENV_NAME
$(printf "%s\n" "${LCL_SETTINGS_TO_ADD[@]}")
$ABK_ENV_END $LCL_ENV_NAME
TEXT_TO_ADD
        fi
    else
        AbkLib_PrintTrace $TRACE_CRITICAL "    ${RED}\tInvalid parameters passed in${NC}"
    fi

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}

AbkLib_RemoveEnvironmentSettings() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_ENV_NAME=$1
    local LCL_FILE_TO_REMOVE_CONTENT_FROM=$2
    local LCL_RESULT=$FALSE

    if [ -f "$LCL_FILE_TO_REMOVE_CONTENT_FROM" ]; then
        echo "   [File $LCL_FILE_TO_REMOVE_CONTENT_FROM exist ...]"
        LCL_RESULT=$TRUE
        if grep -q -e "$ABK_ENV_BEGIN $LCL_ENV_NAME" $LCL_FILE_TO_REMOVE_CONTENT_FROM; then
            AbkLib_PrintTrace $TRACE_INFO "   [ABK environment found removing it...]"
            sed -i -e "/^$ABK_ENV_BEGIN $LCL_ENV_NAME$/,/^$ABK_ENV_END $LCL_ENV_NAME$/d" "$LCL_FILE_TO_REMOVE_CONTENT_FROM"
        else
            AbkLib_PrintTrace $TRACE_INFO "   [ABK environment NOT found. Nothng to remove]"
        fi
    else
        echo "   [File: $LCL_FILE_TO_REMOVE_CONTENT_FROM does not exist.]"
    fi

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}

AbkLib_IsParameterHelp() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local NUMBER_OF_PARAMETERS=$1
    local PARAMETER=$2
    if [ $NUMBER_OF_PARAMETERS -eq 1 ] && [ "$PARAMETER" == "--help" ]; then
        AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (TRUE)"
        return $TRUE
    else
        AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (FALSE)"
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
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
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

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_MATCH_FOUND)"
    return $LCL_MATCH_FOUND
}

AbkLib_IsBrewInstalled() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RESULT=$TRUE
    # homebrew installed?
    if [[ $(command -v brew) == "" ]]; then
        LCL_RESULT=$FALSE
        echo "WARNING: Hombrew is not installed, please install with:"
        echo "/usr/bin/ruby -e \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\""
    fi
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]}($LCL_RESULT)"
    return $LCL_RESULT
}


AbkLib_SourceEnvironment() {
    local LCL_USER_CONFIG_FILE_SHELL=$1
    # todo: find a way to re-fresh environment from the shell script. As of now it does not work for zsh
    # source $LCL_USER_CONFIG_FILE_SHELL
}


AbkLib_CheckNumberOfParameters() {
    AbkLib_PrintTrace $TRACE_FUNCTION "\n    -> ${FUNCNAME[0]} ($@)"
    local LCL_EXPECTED_NUMBER_OF_PARAMS=$1
    shift
    local LCL_PARAMETERS_PASSED_IN=("$@")

    if [ $LCL_EXPECTED_NUMBER_OF_PARAMS -ne ${#LCL_PARAMETERS_PASSED_IN[@]} ]; then
        AbkLib_PrintTrace $TRACE_CRITICAL "${RED}ERROR: invalid number of parameters.${NC}"
        AbkLib_PrintTrace $TRACE_INFO "\texpected number:\t$LCL_EXPECTED_NUMBER_OF_PARAMS"
        AbkLib_PrintTrace $TRACE_INFO "\tpassed in number:\t${#LCL_PARAMETERS_PASSED_IN[@]}"
        AbkLib_PrintTrace $TRACE_INFO "\tparameters passed in:\t${LCL_PARAMETERS_PASSED_IN[@]}"
        AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (FALSE)"
        return $FALSE
    else
        AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} (TRUE)"
        return $TRUE
    fi
}

AbkLib_GetIdLike_linux() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_ID_LIKE="$(cat /etc/os-release | grep '^ID_LIKE=.*' | cut -d'=' -f2)"
    AbkLib_PrintTrace $TRACE_DEBUG "    LCL_LINUX_ID_LIKE = $LCL_LINUX_ID_LIKE"
    [ "$LCL_LINUX_ID_LIKE" == "" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_LINUX_ID_LIKE
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_ID_LIKE)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_linux() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_ID="$(cat /etc/os-release | grep '^ID=.*' | cut -d'=' -f2)"
    [ "$LCL_LINUX_ID" == "" ] && LCL_EXIT_CODE=1
    AbkLib_PrintTrace $TRACE_DEBUG "    LCL_LINUX_ID = $LCL_LINUX_ID"

    eval $LCL_RETURN_VAR=\$LCL_LINUX_ID
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_macOS() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_MACOS_ID="macOS"
    # local LCL_MACOS_ID="$(sw_vers -ProductName)" # that not always gives MacOS
    # [ "$LCL_MACOS_ID" == "" ] && LCL_EXIT_CODE=1 # not needed because it is hard coded now
    AbkLib_PrintTrace $TRACE_DEBUG "    LCL_MACOS_ID = $LCL_MACOS_ID"

    eval $LCL_RETURN_VAR=\$LCL_MACOS_ID
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_MACOS_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetId_unix() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_UNIX_ID=
    AbkLib_GetId_$ABK_UNIX_TYPE LCL_UNIX_ID || LCL_EXIT_CODE=$?

    eval $LCL_RETURN_VAR=\$LCL_UNIX_ID
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_UNIX_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_linux() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_LINUX_VERSION_ID="$(cat /etc/os-release | grep '^VERSION_ID=.*' | cut -d'=' -f2 | sed 's/"//g')"
    AbkLib_PrintTrace $TRACE_DEBUG "    LCL_LINUX_VERSION_ID = $LCL_LINUX_VERSION_ID"
    [ "$LCL_LINUX_VERSION_ID" == "" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_LINUX_VERSION_ID
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_LINUX_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_macOS() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_MACOS_VERSION_ID="$(sw_vers -productVersion | cut -d'.' -f1)"
    AbkLib_PrintTrace $TRACE_DEBUG "    LCL_MACOS_VERSION_ID = $LCL_MACOS_VERSION_ID"
    [ "$LCL_MACOS_VERSION_ID" == "" ] && LCL_EXIT_CODE=1

    eval $LCL_RETURN_VAR=\$LCL_MACOS_VERSION_ID
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_MACOS_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetVersionId_unix() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    local LCL_UNIX_VERSION_ID=
    AbkLib_GetVersionId_$ABK_UNIX_TYPE LCL_UNIX_VERSION_ID || LCL_EXIT_CODE=$?

    eval $LCL_RETURN_VAR=\$LCL_UNIX_VERSION_ID
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE $LCL_UNIX_VERSION_ID)"
    return $LCL_EXIT_CODE
}

AbkLib_GetJsonInstructions() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_JSON_FILE=$2
    local LCL_EXIT_CODE=0
    local LCL_JSON_KEY=".$ABK_UNIX_TYPE"
    local LCL_JSON=$(cat $LCL_JSON_FILE)
    # AbkLib_PrintTrace $TRACE_DEBUG "LCL_JSON = $LCL_JSON"

    if [ "$ABK_UNIX_TYPE" == "linux" ]; then
        AbkLib_GetIdLike_linux LINUX_ID_LIKE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetIdLike_linux failed"
        LCL_JSON_KEY="${LCL_JSON_KEY}.$LINUX_ID_LIKE"
    fi

    local LCL_OS_INSTRACTIONS=$(echo "$LCL_JSON" | jq -r "$LCL_JSON_KEY")
    # AbkLib_PrintTrace $TRACE_DEBUG "    LCL_OS_INSTRACTIONS = $LCL_OS_INSTRACTIONS"

    eval $LCL_RETURN_VAR=\$LCL_OS_INSTRACTIONS
    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}

AbkLib_CheckPreRequisites_macOS() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_EXIT_CODE=0
    local IS_BREW_INSTALLED=$FALSE

    [ "$(command -v brew)" != "" ] && IS_BREW_INSTALLED=$TRUE
    AbkLib_PrintTrace $TRACE_DEBUG "    IS_BREW_INSTALLED = $IS_BREW_INSTALLED"
    if [ "$IS_BREW_INSTALLED" == "$FALSE" ]; then
        AbkLib_PrintTrace $TRACE_INFO '    ERROR: Brew is NOT installed. Please install with: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        AbkLib_PrintTrace $TRACE_INFO '    For details please see: https://brew.sh/'
        LCL_EXIT_CODE=1
    else
        # check jq is installed, we need it to read json tool installation instructions file
        local LCL_JQ='jq'
        local LCL_JQ_INSTALLATION="brew install $LCL_JQ"
        AbkLib_InstallTool "$LCL_JQ" "$LCL_JQ_INSTALLATION" || PrintUsageAndExitWithCode $? "${RED}ERROR: $LCL_JQ installation failed${NC}"
    fi

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckPreRequisites_linux() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_EXIT_CODE=0

    AbkLib_GetIdLike_linux LINUX_ID_LIKE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetIdLike_linux failed"
    AbkLib_PrintTrace $TRACE_DEBUG "    LINUX_ID_LIKE = $LINUX_ID_LIKE"
    AbkLib_IsStringInArray $LINUX_ID_LIKE "${ABK_SUPPORTED_LINUX_ID_LIKE[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $LINUX_ID_LIKE is not supported.\nSupported Linux ID likes are: ${ABK_SUPPORTED_LINUX_ID_LIKE[*]}"

    # check jq is installed, we need it to read json tool installation instructions file
    local LCL_JQ='jq'
    local LCL_JQ_INSTALLATION="sudo apt install -y $LCL_JQ"
    AbkLib_InstallTool "$LCL_JQ" "$LCL_JQ_INSTALLATION" || PrintUsageAndExitWithCode $? "${RED}ERROR: $LCL_JQ installation failed${NC}"

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckPreRequisites() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_EXIT_CODE=0

    # is $SHELL supported
    AbkLib_PrintTrace $TRACE_DEBUG "    ABK_SHELL = $ABK_SHELL"
    AbkLib_IsStringInArray $ABK_SHELL "${ABK_SUPPORTED_SHELLS[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $ABK_SHELL is not supported.\nPlease consider using one of those shells: ${ABK_SUPPORTED_SHELLS[*]}"

    # get unix type
    AbkLib_PrintTrace $TRACE_DEBUG "    ABK_UNIX_TYPE = $ABK_UNIX_TYPE"
    AbkLib_IsStringInArray $ABK_UNIX_TYPE "${ABK_SUPPORTED_UNIX[@]}" || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} $ABK_UNIX_TYPE is not supported.\nSupported Unix types are: ${ABK_SUPPORTED_UNIX[*]}"

    AbkLib_CheckPreRequisites_$ABK_UNIX_TYPE || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} PreRequisites for ${ABK_UNIX_TYPE} are not met"

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_MarkInstalledStep() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_INSTALLED_TYPE=$1
    local LCL_INSTALLED_TOOL=$2
    local LCL_INSTALLED_STEP=$3
    local LCL_EXIT_CODE=0

    local LCL_INSTALLATION_LINE=$(jq --arg type "$LCL_INSTALLED_TYPE" --arg app "$LCL_INSTALLED_TOOL" '.[$type][$app]' "$INSTALLED_DIR/$INSTALLED_FILE" | grep "$LCL_INSTALLED_STEP")
    AbkLib_PrintTrace $TRACE_DEBUG "    LCL_INSTALLATION_LINE =$LCL_INSTALLATION_LINE"
    if [ "$LCL_INSTALLATION_LINE" == "" ]; then
        # If it doesn't exist, add the line to the JSON file
        jq --arg type "$LCL_INSTALLED_TYPE" --arg app "$LCL_INSTALLED_TOOL" --arg step "$LCL_INSTALLED_STEP" \
            '.[$type][$app] += [$step]' "$INSTALLED_DIR/$INSTALLED_FILE" > "$INSTALLED_DIR/$INSTALLED_FILE.tmp" \
            && mv "$INSTALLED_DIR/$INSTALLED_FILE.tmp" "$INSTALLED_DIR/$INSTALLED_FILE"
        [ $? -eq 0 ] && AbkLib_PrintTrace $TRACE_DEBUG "    Line added successfully."
    else
        AbkLib_PrintTrace $TRACE_DEBUG "    Line already exists. Skipped adding."
    fi

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_InstallTool() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} ($@)"
    local LCL_TOOL=$1
    local LCL_INSTALL_INSTRACTIONS=$2
    local LCL_EXIT_CODE=0

    if [ "$(command -v $LCL_TOOL)" = "" ]; then
        AbkLib_PrintTrace $TRACE_INFO "    ${YLW}[$LCL_TOOL installation ...]${NC}"
        local TOOL_INSTALLED=$TRUE

        while IFS= read -r INSTALL_STEP; do
            AbkLib_PrintTrace $TRACE_INFO "    installation step: ${YLW}$INSTALL_STEP${NC}"
            eval "$INSTALL_STEP" && AbkLib_MarkInstalledStep "$INSTALLED_TOOLS" "$LCL_TOOL" "$INSTALL_STEP"
        done <<< "$LCL_INSTALL_INSTRACTIONS"
    else
        AbkLib_PrintTrace $TRACE_INFO "    ${GRN}$LCL_TOOL already installed${NC}"
    fi

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


AbkLib_CheckInstallationCompability() {
    AbkLib_PrintTrace $TRACE_FUNCTION "    -> ${FUNCNAME[0]} (hidden)"
    local LCL_INSTRACTIONS=$1
    local LCL_EXIT_CODE=0
    local CHECK_UNIX_ID=
    local CHECK_UNIX_VERSION_ID=

    AbkLib_GetId_unix CHECK_UNIX_ID || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetId_unix failed"
    AbkLib_GetVersionId_unix CHECK_UNIX_VERSION_ID || PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} AbkLib_GetVersionId_unix failed"
    AbkLib_PrintTrace $TRACE_DEBUG "    CHECK_UNIX_ID               = $CHECK_UNIX_ID"
    AbkLib_PrintTrace $TRACE_DEBUG "    CHECK_UNIX_VERSION_ID       = $CHECK_UNIX_VERSION_ID"

    # check distro name support
    local LCL_MATCH_SUPPORTED_VERSION=$(echo $LCL_INSTRACTIONS | jq -r ".supported_versions.$CHECK_UNIX_ID[] | select(.==\"$CHECK_UNIX_VERSION_ID\")")
    AbkLib_PrintTrace $TRACE_DEBUG "    LCL_MATCH_SUPPORTED_VERSION = $LCL_MATCH_SUPPORTED_VERSION"
    [ "$LCL_MATCH_SUPPORTED_VERSION" == "" ] && PrintUsageAndExitWithCode $? "${RED}ERROR:${NC} UnixId: $CHECK_UNIX_ID with version: $CHECK_UNIX_VERSION_ID is not supported.\nSupported Unix types are: $(echo $LCL_INSTRACTIONS | jq -r ".supported_versions")"

    AbkLib_PrintTrace $TRACE_FUNCTION "    <- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}
