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
    echo "$0 - sets claude AI agent environment"
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
    local LCL_REQUIRED_TOOLS=(
        rsync
    )

    if ! command -v claude &>/dev/null; then
        PrintTrace "$TRACE_INFO" "Install claude manually with: npm install -g @anthropic-ai/claude-code"
        PrintTrace "$TRACE_INFO" "Or better install AI tools including claude with: ./install.sh tools_ai.json"
        LCL_EXIT_CODE=1
    fi

    for LCL_TOOL in "${LCL_REQUIRED_TOOLS[@]}"; do
        if ! command -v "$LCL_TOOL" &>/dev/null; then
            if [ "$ABK_UNIX_TYPE" = "macOS" ]; then
                brew install "$LCL_TOOL" || { PrintTrace "$TRACE_ERROR" "${RED}❌ Required tool '$LCL_TOOL' installation failed.${NC}"; LCL_EXIT_CODE=1;}
            elif [ "$ABK_UNIX_TYPE" = "linux" ]; then
                sudo apt install -y "$LCL_TOOL" || { PrintTrace "$TRACE_ERROR" "${RED}❌ Required tool '$LCL_TOOL' installation failed.${NC}"; LCL_EXIT_CODE=1;}
            else
                PrintTrace "$TRACE_ERROR" "${RED}❌ Unknown OS type: $ABK_UNIX_TYPE${NC}"
                return 1
            fi
        fi
    done

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


createClaudeDir() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0

    PrintTrace "$TRACE_DEBUG" "CLAUDE_DIR = $CLAUDE_DIR"
    if [ -d "$CLAUDE_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[$CLAUDE_DIR already created]"
    else
        PrintTrace "$TRACE_INFO" "[Creating $CLAUDE_DIR directory]"
        mkdir -p "$CLAUDE_DIR"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


createClaudeCommandLinks() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_CURRENT_DIR=$PWD
    local LCL_ABK_CLAUDE_BACKUP_DIR="$LCL_CURRENT_DIR/unixBin/env/claude_backup"
    local LCL_ABK_CLAUDE_BACKUP_CMDS_DIR="$LCL_ABK_CLAUDE_BACKUP_DIR/commands"
    local LCL_EXIT_CODE=0

    local LCL_CLAUDE_CMDS_DIR="$CLAUDE_DIR/commands"
    local LCL_ABK_CLAUDE_CMDS_DIR="$LCL_CURRENT_DIR/unixBin/env/claude/commands"

    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_CMDS_DIR = $LCL_CLAUDE_CMDS_DIR"
    PrintTrace "$TRACE_DEBUG" "LCL_ABK_CLAUDE_CMDS_DIR = $LCL_ABK_CLAUDE_CMDS_DIR"
    PrintTrace "$TRACE_DEBUG" "LCL_ABK_CLAUDE_BACKUP_CMDS_DIR = $LCL_ABK_CLAUDE_BACKUP_CMDS_DIR"

    # Ensure backup directory exists
    mkdir -p "$LCL_ABK_CLAUDE_BACKUP_DIR"

    # Check if ~/.claude/commands exists and is not a symlink
    if [ -d "$LCL_CLAUDE_CMDS_DIR" ] && [ ! -L "$LCL_CLAUDE_CMDS_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Found existing commands directory - backing up to $LCL_ABK_CLAUDE_BACKUP_CMDS_DIR]"

        # Remove old backup if it exists
        [ -d "$LCL_ABK_CLAUDE_BACKUP_CMDS_DIR" ] && rm -rf "$LCL_ABK_CLAUDE_BACKUP_CMDS_DIR"

        # Move existing commands to backup
        mv "$LCL_CLAUDE_CMDS_DIR" "$LCL_ABK_CLAUDE_BACKUP_CMDS_DIR"

        # Merge backed up commands into git repo commands (only copy files that don't exist)
        if [ -d "$LCL_ABK_CLAUDE_BACKUP_CMDS_DIR" ]; then
            PrintTrace "$TRACE_INFO" "[Merging unique commands from backup into git repo]"
            rsync -av --ignore-existing "$LCL_ABK_CLAUDE_BACKUP_CMDS_DIR"/*.md "$LCL_ABK_CLAUDE_CMDS_DIR"/ 2>/dev/null || true
        fi
    elif [ -L "$LCL_CLAUDE_CMDS_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Commands directory is already a symlink - removing it]"
        rm "$LCL_CLAUDE_CMDS_DIR"
    fi

    # Ensure the target directory exists
    mkdir -p "$LCL_ABK_CLAUDE_CMDS_DIR"

    # Create the symlink
    PrintTrace "$TRACE_INFO" "[Creating symlink: $LCL_CLAUDE_CMDS_DIR -> $LCL_ABK_CLAUDE_CMDS_DIR]"
    ln -s "$LCL_ABK_CLAUDE_CMDS_DIR" "$LCL_CLAUDE_CMDS_DIR" || LCL_EXIT_CODE=$?

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
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
createClaudeDir || PrintUsageAndExitWithCode $? "${RED}❌ createClaudeDir failed. Aborting.${NC}"
createClaudeCommandLinks || PrintUsageAndExitWithCode $? "${RED}❌ createClaudeCommandLinks failed. Aborting.${NC}"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
