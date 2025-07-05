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


removeClaudeCommandLinks() {
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

    # Check if symlink exists and remove it
    if [ -L "$LCL_CLAUDE_CMDS_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Removing symlink: $LCL_CLAUDE_CMDS_DIR]"
        rm "$LCL_CLAUDE_CMDS_DIR"
    elif [ -d "$LCL_CLAUDE_CMDS_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Commands directory is not a symlink - leaving as is]"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
        return 0
    fi

    # Check if backup exists to restore
    if [ -d "$LCL_ABK_CLAUDE_BACKUP_CMDS_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Restoring original commands from backup: $LCL_ABK_CLAUDE_BACKUP_CMDS_DIR -> $LCL_CLAUDE_CMDS_DIR]"

        # Move backup commands back to original location
        mv "$LCL_ABK_CLAUDE_BACKUP_CMDS_DIR" "$LCL_CLAUDE_CMDS_DIR"

        # Clean up empty backup directory if it exists
        if [ -d "$LCL_ABK_CLAUDE_BACKUP_DIR" ] && [ -z "$(ls -A "$LCL_ABK_CLAUDE_BACKUP_DIR")" ]; then
            PrintTrace "$TRACE_INFO" "[Cleaning up empty backup directory: $LCL_ABK_CLAUDE_BACKUP_DIR]"
            rmdir "$LCL_ABK_CLAUDE_BACKUP_DIR"
        fi

        PrintTrace "$TRACE_INFO" "[Commands successfully restored to original state]"
    else
        PrintTrace "$TRACE_INFO" "[No backup found - creating empty commands directory]"
        mkdir -p "$LCL_CLAUDE_CMDS_DIR"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


removeClaudeConfigLinks() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_CURRENT_DIR=$PWD
    local LCL_ABK_CLAUDE_BACKUP_DIR="$LCL_CURRENT_DIR/unixBin/env/claude_backup"
    local LCL_ABK_CLAUDE_BACKUP_CONFIG_DIR="$LCL_ABK_CLAUDE_BACKUP_DIR/config"
    local LCL_EXIT_CODE=0

    local LCL_CLAUDE_CONFIG_DIR="$CLAUDE_DIR/config"
    
    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_CONFIG_DIR = $LCL_CLAUDE_CONFIG_DIR"
    PrintTrace "$TRACE_DEBUG" "LCL_ABK_CLAUDE_BACKUP_CONFIG_DIR = $LCL_ABK_CLAUDE_BACKUP_CONFIG_DIR"
    
    # Remove generated config directory (not symlinked, but generated)
    if [ -d "$LCL_CLAUDE_CONFIG_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Removing generated config directory: $LCL_CLAUDE_CONFIG_DIR]"
        rm -rf "$LCL_CLAUDE_CONFIG_DIR"
    fi
    
    # Check if backup exists to restore
    if [ -d "$LCL_ABK_CLAUDE_BACKUP_CONFIG_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Restoring original config from backup: $LCL_ABK_CLAUDE_BACKUP_CONFIG_DIR -> $LCL_CLAUDE_CONFIG_DIR]"
        
        # Move backup config back to original location
        mv "$LCL_ABK_CLAUDE_BACKUP_CONFIG_DIR" "$LCL_CLAUDE_CONFIG_DIR"
        
        PrintTrace "$TRACE_INFO" "[Config successfully restored to original state]"
    else
        PrintTrace "$TRACE_INFO" "[No config backup found - skipping restoration]"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


removeClaudeTemplateLinks() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_CURRENT_DIR=$PWD
    local LCL_ABK_CLAUDE_BACKUP_DIR="$LCL_CURRENT_DIR/unixBin/env/claude_backup"
    local LCL_ABK_CLAUDE_BACKUP_TEMPLATES_DIR="$LCL_ABK_CLAUDE_BACKUP_DIR/templates"
    local LCL_EXIT_CODE=0

    local LCL_CLAUDE_TEMPLATES_DIR="$CLAUDE_DIR/templates"
    
    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_TEMPLATES_DIR = $LCL_CLAUDE_TEMPLATES_DIR"
    PrintTrace "$TRACE_DEBUG" "LCL_ABK_CLAUDE_BACKUP_TEMPLATES_DIR = $LCL_ABK_CLAUDE_BACKUP_TEMPLATES_DIR"
    
    # Check if symlink exists and remove it
    if [ -L "$LCL_CLAUDE_TEMPLATES_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Removing symlink: $LCL_CLAUDE_TEMPLATES_DIR]"
        rm "$LCL_CLAUDE_TEMPLATES_DIR"
    elif [ -d "$LCL_CLAUDE_TEMPLATES_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Templates directory is not a symlink - leaving as is]"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
        return 0
    fi
    
    # Check if backup exists to restore
    if [ -d "$LCL_ABK_CLAUDE_BACKUP_TEMPLATES_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Restoring original templates from backup: $LCL_ABK_CLAUDE_BACKUP_TEMPLATES_DIR -> $LCL_CLAUDE_TEMPLATES_DIR]"
        
        # Move backup templates back to original location
        mv "$LCL_ABK_CLAUDE_BACKUP_TEMPLATES_DIR" "$LCL_CLAUDE_TEMPLATES_DIR"
        
        PrintTrace "$TRACE_INFO" "[Templates successfully restored to original state]"
    else
        PrintTrace "$TRACE_INFO" "[No templates backup found - creating empty templates directory]"
        mkdir -p "$LCL_CLAUDE_TEMPLATES_DIR"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


removeClaudeWorkspaceLinks() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_CURRENT_DIR=$PWD
    local LCL_ABK_CLAUDE_BACKUP_DIR="$LCL_CURRENT_DIR/unixBin/env/claude_backup"
    local LCL_ABK_CLAUDE_BACKUP_WORKSPACES_DIR="$LCL_ABK_CLAUDE_BACKUP_DIR/workspaces"
    local LCL_EXIT_CODE=0

    local LCL_CLAUDE_WORKSPACES_DIR="$CLAUDE_DIR/workspaces"
    
    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_WORKSPACES_DIR = $LCL_CLAUDE_WORKSPACES_DIR"
    PrintTrace "$TRACE_DEBUG" "LCL_ABK_CLAUDE_BACKUP_WORKSPACES_DIR = $LCL_ABK_CLAUDE_BACKUP_WORKSPACES_DIR"
    
    # Check if symlink exists and remove it
    if [ -L "$LCL_CLAUDE_WORKSPACES_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Removing symlink: $LCL_CLAUDE_WORKSPACES_DIR]"
        rm "$LCL_CLAUDE_WORKSPACES_DIR"
    elif [ -d "$LCL_CLAUDE_WORKSPACES_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Workspaces directory is not a symlink - leaving as is]"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
        return 0
    fi
    
    # Check if backup exists to restore
    if [ -d "$LCL_ABK_CLAUDE_BACKUP_WORKSPACES_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Restoring original workspaces from backup: $LCL_ABK_CLAUDE_BACKUP_WORKSPACES_DIR -> $LCL_CLAUDE_WORKSPACES_DIR]"
        
        # Move backup workspaces back to original location
        mv "$LCL_ABK_CLAUDE_BACKUP_WORKSPACES_DIR" "$LCL_CLAUDE_WORKSPACES_DIR"
        
        PrintTrace "$TRACE_INFO" "[Workspaces successfully restored to original state]"
    else
        PrintTrace "$TRACE_INFO" "[No workspaces backup found - creating empty workspaces directory]"
        mkdir -p "$LCL_CLAUDE_WORKSPACES_DIR"
    fi

    # Clean up empty backup directory if it exists
    if [ -d "$LCL_ABK_CLAUDE_BACKUP_DIR" ] && [ -z "$(ls -A "$LCL_ABK_CLAUDE_BACKUP_DIR")" ]; then
        PrintTrace "$TRACE_INFO" "[Cleaning up empty backup directory: $LCL_ABK_CLAUDE_BACKUP_DIR]"
        rmdir "$LCL_ABK_CLAUDE_BACKUP_DIR"
    fi

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
removeClaudeWorkspaceLinks || PrintUsageAndExitWithCode $? "${RED}❌ removeClaudeWorkspaceLinks failed. Aborting.${NC}"
removeClaudeTemplateLinks || PrintUsageAndExitWithCode $? "${RED}❌ removeClaudeTemplateLinks failed. Aborting.${NC}"
removeClaudeConfigLinks || PrintUsageAndExitWithCode $? "${RED}❌ removeClaudeConfigLinks failed. Aborting.${NC}"
removeClaudeCommandLinks || PrintUsageAndExitWithCode $? "${RED}❌ removeClaudeCommandLinks failed. Aborting.${NC}"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
