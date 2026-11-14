#!/usr/bin/env bash

#------------------------------------------------------------------------------
# setPass.sh - set up the pass password stores and ~/.envrc_common
#
# Clones each password store from git and wires it up for the shell and direnv.
# No parameters. Safe to re-run: existing clones are updated (git pull).
# Undo with: ./unixBin/resetPass.sh
#
# Stores (see PASS_STORES below):
#   passabk -> ~/.psws_abk/secrets  repo psws_abk = whole ~/.psws_abk folder
#                                   (has its own .envrc and secrets/)
#   passta  -> ~/.psws_ta/secrets   repo psws_ta  = the store itself;
#                                   ~/.psws_ta/.envrc is created by this script
#
# What it does:
#   1. Checks tools: pass, gpg, git, direnv
#   2. Per store:
#      - clones the repo, or git pull --ff-only if already cloned
#      - creates <store root>/.envrc (export PASSWORD_STORE_DIR="$PWD/secrets")
#        if missing, and runs 'direnv allow' on it - so 'cd ~/.psws_ta' and
#        plain 'pass ...' uses that store
#      - checks the store's .gpg-id recipients against your keyring:
#          * none of your secret keys (YubiKey or software) listed -> error,
#            you can't decrypt this store
#          * public keys missing -> warning: reading works, but 'pass insert'
#            and 'pass edit' fail until those keys are imported
#   3. Links ~/.envrc_common -> unixBin/env/envrc_common (passabk/passta as
#      functions for use in a project's .envrc via source_env)
#
# Notes:
#   - Cloning uses SSH - your YubiKey SSH setup (setYkGpg.sh) must work.
#   - Reading secrets needs a YubiKey (or software key) listed in .gpg-id.
#   - Interactive shells get passabk/passta from unixBin/env/002_aliases.env.
#------------------------------------------------------------------------------

#---------------------------
# variables definitions
#---------------------------
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=0
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(dirname "$0")
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"
ENVRC_COMMON_TARGET="$HOME/.envrc_common"

# name | git remote | clone dir | store dir (PASSWORD_STORE_DIR)
PASS_STORES=(
    "abk|git@github.com:alexbigkid/psws_abk.git|$HOME/.psws_abk|$HOME/.psws_abk/secrets"
    "ta|git@github.com:alexbigkid/psws_ta.git|$HOME/.psws_ta/secrets|$HOME/.psws_ta/secrets"
)


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - sets up pass password stores and ~/.envrc_common"
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
    local LCL_TOOL

    for LCL_TOOL in pass gpg git direnv; do
        if ! command -v "$LCL_TOOL" &>/dev/null; then
            PrintTrace "$TRACE_ERROR" "${RED}❌ Required tool '$LCL_TOOL' is not installed (e.g. ./install.sh tools_abk.json)${NC}"
            LCL_EXIT_CODE=1
        fi
    done

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Clone the store repo, or update an existing clone.
cloneOrUpdateStore() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_NAME="$1"
    local LCL_REMOTE="$2"
    local LCL_CLONE_DIR="$3"
    local LCL_EXIT_CODE=0

    if [ -d "$LCL_CLONE_DIR/.git" ]; then
        local LCL_CURRENT_REMOTE
        LCL_CURRENT_REMOTE=$(git -C "$LCL_CLONE_DIR" remote get-url origin 2>/dev/null || true)
        if [ "$LCL_CURRENT_REMOTE" != "$LCL_REMOTE" ]; then
            PrintTrace "$TRACE_INFO" "${YLW}⚠️  [$LCL_NAME] $LCL_CLONE_DIR has origin '$LCL_CURRENT_REMOTE', expected '$LCL_REMOTE' - not updating${NC}"
        elif git -C "$LCL_CLONE_DIR" pull --ff-only --quiet; then
            PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] updated: $LCL_CLONE_DIR"
        else
            PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] git pull failed in $LCL_CLONE_DIR (local changes?)${NC}"
            LCL_EXIT_CODE=1
        fi
    elif [ -e "$LCL_CLONE_DIR" ] && [ -n "$(ls -A "$LCL_CLONE_DIR" 2>/dev/null)" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] $LCL_CLONE_DIR exists but is not a git clone - leaving it alone${NC}"
        LCL_EXIT_CODE=1
    else
        mkdir -p "$(dirname "$LCL_CLONE_DIR")"
        if git clone --quiet "$LCL_REMOTE" "$LCL_CLONE_DIR"; then
            PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] cloned $LCL_REMOTE -> $LCL_CLONE_DIR"
        else
            PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] git clone failed: $LCL_REMOTE${NC}"
            LCL_EXIT_CODE=1
        fi
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Make 'cd <store root>' select the store: <root>/.envrc sets PASSWORD_STORE_DIR.
setupStoreEnvrc() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_NAME="$1"
    local LCL_STORE_DIR="$2"
    local LCL_ROOT_DIR
    LCL_ROOT_DIR=$(dirname "$LCL_STORE_DIR")
    local LCL_ENVRC="$LCL_ROOT_DIR/.envrc"
    local LCL_EXIT_CODE=0

    if [ -f "$LCL_ENVRC" ]; then
        PrintTrace "$TRACE_INFO" "ℹ️  [$LCL_NAME] $LCL_ENVRC already exists - keeping it"
    else
        printf '%s\n' '# created by abk_env/unixBin/setPass.sh' 'export PASSWORD_STORE_DIR="$PWD/secrets"' > "$LCL_ENVRC"
        PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] created $LCL_ENVRC"
    fi

    if direnv allow "$LCL_ROOT_DIR"; then
        PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] direnv allowed: $LCL_ENVRC"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] direnv allow failed for $LCL_ENVRC${NC}"
        LCL_EXIT_CODE=1
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Check the store's .gpg-id recipients against the keyring.
checkStoreRecipients() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_NAME="$1"
    local LCL_STORE_DIR="$2"
    local LCL_GPG_ID_FILE="$LCL_STORE_DIR/.gpg-id"
    local LCL_EXIT_CODE=0
    local LCL_RECIPIENT LCL_SECRET_COUNT=0
    local LCL_MISSING=()

    if [ ! -f "$LCL_GPG_ID_FILE" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] no .gpg-id in $LCL_STORE_DIR - not a pass store?${NC}"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (1)"
        return 1
    fi

    while read -r LCL_RECIPIENT; do
        [ -z "$LCL_RECIPIENT" ] && continue
        [[ "$LCL_RECIPIENT" == \#* ]] && continue
        if ! gpg --list-keys "$LCL_RECIPIENT" >/dev/null 2>&1; then
            LCL_MISSING+=("$LCL_RECIPIENT")
        elif gpg --list-secret-keys --with-colons "$LCL_RECIPIENT" 2>/dev/null | awk -F: '($1=="ssb"||$1=="sec") && $15!="" && $15!="#" {f=1} END {exit !f}'; then
            LCL_SECRET_COUNT=$((LCL_SECRET_COUNT + 1))
        fi
    done < "$LCL_GPG_ID_FILE"

    if [ "$LCL_SECRET_COUNT" -eq 0 ]; then
        PrintTrace "$TRACE_ERROR" "${RED}❌ [$LCL_NAME] none of your secret keys is in $LCL_GPG_ID_FILE - you can't decrypt this store${NC}"
        LCL_EXIT_CODE=1
    else
        PrintTrace "$TRACE_INFO" "✅ [$LCL_NAME] decryptable with $LCL_SECRET_COUNT of your keys"
    fi

    if [ ${#LCL_MISSING[@]} -ne 0 ]; then
        PrintTrace "$TRACE_INFO" "${YLW}⚠️  [$LCL_NAME] public keys missing from keyring: ${LCL_MISSING[*]}${NC}"
        PrintTrace "$TRACE_INFO" "${YLW}   Reading works, but 'pass insert/edit' fails until imported (gpg --import <key>.asc)${NC}"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


# Link ~/.envrc_common to the git-controlled copy. A real file is moved aside.
linkEnvrcCommon() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_SOURCE
    LCL_SOURCE="$(cd "$SCRIPT_PATH" && pwd)/env/envrc_common"
    local LCL_EXIT_CODE=0

    if [ -L "$ENVRC_COMMON_TARGET" ]; then
        rm "$ENVRC_COMMON_TARGET"
    elif [ -e "$ENVRC_COMMON_TARGET" ]; then
        local LCL_BACKUP
        LCL_BACKUP="$ENVRC_COMMON_TARGET.bak.$(date +%Y%m%d%H%M%S)"
        mv "$ENVRC_COMMON_TARGET" "$LCL_BACKUP"
        PrintTrace "$TRACE_INFO" "${YLW}⚠️  existing $ENVRC_COMMON_TARGET moved to $LCL_BACKUP${NC}"
    fi

    if ln -s "$LCL_SOURCE" "$ENVRC_COMMON_TARGET"; then
        PrintTrace "$TRACE_INFO" "✅ linked $ENVRC_COMMON_TARGET -> $LCL_SOURCE"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ failed to link $ENVRC_COMMON_TARGET${NC}"
        LCL_EXIT_CODE=1
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

[ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode 0
[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS${NC}"

checkPrerequisiteToolsAreInstalled || PrintUsageAndExitWithCode 1 "${RED}❌ Required tools missing. Aborting.${NC}"

# Best effort: set up every store, remember failures
for STORE in "${PASS_STORES[@]}"; do
    IFS='|' read -r STORE_NAME STORE_REMOTE STORE_CLONE_DIR STORE_DIR <<< "$STORE"
    PrintTrace "$TRACE_INFO" "🔐 [$STORE_NAME] $STORE_DIR"
    if cloneOrUpdateStore "$STORE_NAME" "$STORE_REMOTE" "$STORE_CLONE_DIR"; then
        setupStoreEnvrc "$STORE_NAME" "$STORE_DIR"      || EXIT_CODE=1
        checkStoreRecipients "$STORE_NAME" "$STORE_DIR" || EXIT_CODE=1
    else
        EXIT_CODE=1
    fi
done

linkEnvrcCommon || EXIT_CODE=1

if [ $EXIT_CODE -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "✅ Password stores ready. Try: passta ls"
else
    PrintTrace "$TRACE_ERROR" "${RED}❌ Finished with errors - see messages above.${NC}"
fi

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
