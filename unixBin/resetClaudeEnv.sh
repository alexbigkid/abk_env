#!/usr/bin/env bash

#---------------------------
# variables definitions
#---------------------------
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=0
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(dirname "$0")
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"
CLAUDE_DIR="$HOME/.claude"


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - resets claude AI agent environment to original state"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo "$2"
    exit "$1"
}


checkPrerequisiteToolsAreInstalled () {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0

    if ! command -v claude &>/dev/null; then
        PrintTrace "$TRACE_INFO" "Install claude manually with: npm install -g @anthropic-ai/claude-code"
        PrintTrace "$TRACE_INFO" "Or better install AI tools including claude with: ./install.sh tools_ai.json"
        LCL_EXIT_CODE=1
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


# Remove the ~/.claude/<subdir> symlink, leaving git-controlled files untouched.
# If the path is a real directory (not a symlink), it is left alone to avoid
# clobbering anything the user may have put there outside this setup.
unlinkClaudeSubdir() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_SUBDIR_NAME="$1"
    local LCL_CLAUDE_TARGET="$CLAUDE_DIR/$LCL_SUBDIR_NAME"

    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_TARGET = $LCL_CLAUDE_TARGET"

    if [ -L "$LCL_CLAUDE_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "[Removing symlink: $LCL_CLAUDE_TARGET]"
        rm "$LCL_CLAUDE_TARGET"
    elif [ -d "$LCL_CLAUDE_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "[$LCL_SUBDIR_NAME is not a symlink - leaving as is]"
    else
        PrintTrace "$TRACE_INFO" "[No $LCL_SUBDIR_NAME directory or symlink to remove]"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


# Remove the ~/.claude/<file> symlink, leaving the git-controlled file untouched.
# If the target is a real file (not a symlink), it is left alone.
unlinkClaudeFile() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_FILE_NAME="$1"
    local LCL_CLAUDE_TARGET="$CLAUDE_DIR/$LCL_FILE_NAME"

    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_TARGET = $LCL_CLAUDE_TARGET"

    if [ -L "$LCL_CLAUDE_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "[Removing symlink: $LCL_CLAUDE_TARGET]"
        rm "$LCL_CLAUDE_TARGET"
    elif [ -f "$LCL_CLAUDE_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "[$LCL_FILE_NAME is not a symlink - leaving as is]"
    else
        PrintTrace "$TRACE_INFO" "[No $LCL_FILE_NAME file or symlink to remove]"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


# Remove only the config files generated from templates, preserving anything
# the user added by hand. Secrets in generated files are cleaned up; user
# customizations survive a reset.
removeGeneratedConfig() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_CLAUDE_CONFIG_DIR="$CLAUDE_DIR/config"
    local LCL_ABK_CLAUDE_CONFIG_DIR="$PWD/unixBin/env/claude/config"

    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_CONFIG_DIR = $LCL_CLAUDE_CONFIG_DIR"

    if [ ! -d "$LCL_CLAUDE_CONFIG_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[No config directory to clean up]"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
        return 0
    fi

    for template_file in "$LCL_ABK_CLAUDE_CONFIG_DIR"/*.template.*; do
        if [ -f "$template_file" ]; then
            local LCL_FILE_NAME
            LCL_FILE_NAME=$(basename "$template_file")
            local LCL_GENERATED_FILE="$LCL_CLAUDE_CONFIG_DIR/${LCL_FILE_NAME/.template/}"
            if [ -f "$LCL_GENERATED_FILE" ]; then
                PrintTrace "$TRACE_INFO" "[Removing generated config file: $LCL_GENERATED_FILE]"
                rm -f "$LCL_GENERATED_FILE"
            fi
        fi
    done

    # If nothing user-added remains, remove the empty directory
    if [ -z "$(ls -A "$LCL_CLAUDE_CONFIG_DIR" 2>/dev/null)" ]; then
        PrintTrace "$TRACE_INFO" "[Removing empty config directory: $LCL_CLAUDE_CONFIG_DIR]"
        rmdir "$LCL_CLAUDE_CONFIG_DIR" 2>/dev/null || true
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
PrintTrace "$TRACE_DEBUG" "SCRIPT_PATH = $SCRIPT_PATH"
PrintTrace "$TRACE_DEBUG" "ABK_LIB_FILE = $ABK_LIB_FILE"

# Check for help parameter
[ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode 0

# Check parameter count
[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS${NC}"
set -e

checkPrerequisiteToolsAreInstalled || PrintUsageAndExitWithCode $? "${RED}❌ claude is not installed. Please install claude. Aborting.${NC}"
unlinkClaudeFile   CLAUDE.md  || PrintUsageAndExitWithCode $? "${RED}❌ unlinkClaudeFile CLAUDE.md failed. Aborting.${NC}"
unlinkClaudeSubdir skills     || PrintUsageAndExitWithCode $? "${RED}❌ unlinkClaudeSubdir skills failed. Aborting.${NC}"
unlinkClaudeSubdir workspaces || PrintUsageAndExitWithCode $? "${RED}❌ unlinkClaudeSubdir workspaces failed. Aborting.${NC}"
unlinkClaudeSubdir templates  || PrintUsageAndExitWithCode $? "${RED}❌ unlinkClaudeSubdir templates failed. Aborting.${NC}"
unlinkClaudeSubdir commands   || PrintUsageAndExitWithCode $? "${RED}❌ unlinkClaudeSubdir commands failed. Aborting.${NC}"
removeGeneratedConfig         || PrintUsageAndExitWithCode $? "${RED}❌ removeGeneratedConfig failed. Aborting.${NC}"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
