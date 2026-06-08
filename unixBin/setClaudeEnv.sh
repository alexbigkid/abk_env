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
        envsubst
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


# Link ~/.claude/<subdir> to the git-controlled copy at unixBin/env/claude/<subdir>.
# If a non-symlink directory already exists at the target, its unique files are
# merged into the git repo first (existing git files win), then the original
# is removed. No separate backup is kept — the git repo is the source of truth.
linkClaudeSubdir() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_SUBDIR_NAME="$1"
    local LCL_EXIT_CODE=0
    local LCL_CLAUDE_TARGET="$CLAUDE_DIR/$LCL_SUBDIR_NAME"
    local LCL_ABK_SOURCE="$PWD/unixBin/env/claude/$LCL_SUBDIR_NAME"

    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_TARGET = $LCL_CLAUDE_TARGET"
    PrintTrace "$TRACE_DEBUG" "LCL_ABK_SOURCE = $LCL_ABK_SOURCE"

    mkdir -p "$LCL_ABK_SOURCE"

    if [ -L "$LCL_CLAUDE_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "[$LCL_SUBDIR_NAME is already a symlink - removing it]"
        rm "$LCL_CLAUDE_TARGET"
    elif [ -d "$LCL_CLAUDE_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "[Merging existing $LCL_SUBDIR_NAME into git repo (git files take priority)]"
        rsync -a --ignore-existing "$LCL_CLAUDE_TARGET"/ "$LCL_ABK_SOURCE"/ 2>/dev/null || true
        rm -rf "$LCL_CLAUDE_TARGET"
    fi

    PrintTrace "$TRACE_INFO" "[Creating symlink: $LCL_CLAUDE_TARGET -> $LCL_ABK_SOURCE]"
    ln -s "$LCL_ABK_SOURCE" "$LCL_CLAUDE_TARGET" || LCL_EXIT_CODE=$?

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Link ~/.claude/<file> to the git-controlled copy at unixBin/env/claude/<file>.
# If the target is a real file and the git copy does not exist yet, the local
# file is copied into the repo first (preserving user content on first setup).
# If both exist, the git version wins.
linkClaudeFile() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_FILE_NAME="$1"
    local LCL_EXIT_CODE=0
    local LCL_CLAUDE_TARGET="$CLAUDE_DIR/$LCL_FILE_NAME"
    local LCL_ABK_SOURCE="$PWD/unixBin/env/claude/$LCL_FILE_NAME"

    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_TARGET = $LCL_CLAUDE_TARGET"
    PrintTrace "$TRACE_DEBUG" "LCL_ABK_SOURCE = $LCL_ABK_SOURCE"

    if [ -L "$LCL_CLAUDE_TARGET" ]; then
        PrintTrace "$TRACE_INFO" "[$LCL_FILE_NAME is already a symlink - removing it]"
        rm "$LCL_CLAUDE_TARGET"
    elif [ -f "$LCL_CLAUDE_TARGET" ]; then
        if [ ! -f "$LCL_ABK_SOURCE" ]; then
            PrintTrace "$TRACE_INFO" "[Copying existing $LCL_FILE_NAME into git repo (preserving user content)]"
            cp "$LCL_CLAUDE_TARGET" "$LCL_ABK_SOURCE"
        else
            PrintTrace "$TRACE_INFO" "[$LCL_FILE_NAME already in git repo - discarding local copy (git wins)]"
        fi
        rm "$LCL_CLAUDE_TARGET"
    fi

    if [ ! -f "$LCL_ABK_SOURCE" ]; then
        PrintTrace "$TRACE_INFO" "[No git-controlled $LCL_FILE_NAME exists - skipping symlink]"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
        return 0
    fi

    PrintTrace "$TRACE_INFO" "[Creating symlink: $LCL_CLAUDE_TARGET -> $LCL_ABK_SOURCE]"
    ln -s "$LCL_ABK_SOURCE" "$LCL_CLAUDE_TARGET" || LCL_EXIT_CODE=$?

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Generate config files from *.template.* by substituting environment variables.
# Files are written directly into ~/.claude/config/ (not symlinked) because
# they contain secrets and must stay outside the git repo.
processConfigTemplates() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    local LCL_ABK_CLAUDE_CONFIG_DIR="$PWD/unixBin/env/claude/config"
    local LCL_CLAUDE_CONFIG_DIR="$CLAUDE_DIR/config"

    PrintTrace "$TRACE_DEBUG" "LCL_ABK_CLAUDE_CONFIG_DIR = $LCL_ABK_CLAUDE_CONFIG_DIR"
    PrintTrace "$TRACE_DEBUG" "LCL_CLAUDE_CONFIG_DIR = $LCL_CLAUDE_CONFIG_DIR"

    # If config is a stale symlink from earlier versions, replace it with a real dir
    if [ -L "$LCL_CLAUDE_CONFIG_DIR" ]; then
        PrintTrace "$TRACE_INFO" "[Config directory is a symlink - removing it]"
        rm "$LCL_CLAUDE_CONFIG_DIR"
    fi

    mkdir -p "$LCL_CLAUDE_CONFIG_DIR"

    for template_file in "$LCL_ABK_CLAUDE_CONFIG_DIR"/*.template.*; do
        if [ -f "$template_file" ]; then
            local LCL_FILE_NAME
            LCL_FILE_NAME=$(basename "$template_file")
            local LCL_OUTPUT_FILE="$LCL_CLAUDE_CONFIG_DIR/${LCL_FILE_NAME/.template/}"

            PrintTrace "$TRACE_INFO" "[Processing template: $LCL_FILE_NAME -> $(basename "$LCL_OUTPUT_FILE")]"

            if envsubst < "$template_file" > "$LCL_OUTPUT_FILE"; then
                chmod 600 "$LCL_OUTPUT_FILE"
                PrintTrace "$TRACE_DEBUG" "Generated config file: $LCL_OUTPUT_FILE"
            else
                PrintTrace "$TRACE_ERROR" "${RED}ERROR: Failed to process template $template_file${NC}"
                LCL_EXIT_CODE=1
            fi
        fi
    done

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
createClaudeDir       || PrintUsageAndExitWithCode $? "${RED}❌ createClaudeDir failed. Aborting.${NC}"
linkClaudeSubdir commands   || PrintUsageAndExitWithCode $? "${RED}❌ linkClaudeSubdir commands failed. Aborting.${NC}"
linkClaudeSubdir templates  || PrintUsageAndExitWithCode $? "${RED}❌ linkClaudeSubdir templates failed. Aborting.${NC}"
linkClaudeSubdir workspaces || PrintUsageAndExitWithCode $? "${RED}❌ linkClaudeSubdir workspaces failed. Aborting.${NC}"
linkClaudeSubdir skills     || PrintUsageAndExitWithCode $? "${RED}❌ linkClaudeSubdir skills failed. Aborting.${NC}"
linkClaudeFile   CLAUDE.md  || PrintUsageAndExitWithCode $? "${RED}❌ linkClaudeFile CLAUDE.md failed. Aborting.${NC}"
processConfigTemplates      || PrintUsageAndExitWithCode $? "${RED}❌ processConfigTemplates failed. Aborting.${NC}"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
