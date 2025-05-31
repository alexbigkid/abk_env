#!/usr/bin/env bash
set -euo pipefail

#---------------------------
# variables
#---------------------------
ABK_LIB_FILE="./unixBin/abkLib.sh"
UNIX_PACKAGES_DIR="./unixPackages"


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


ValidatePackageUninstall() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_INSTALLATION_FILE=$1
    local LCL_FULL_PATH_INSTALLED_FILE="$UNIX_PACKAGES_DIR/$LCL_INSTALLATION_FILE"
    local LCL_FULL_PATH_VALIDATION_FILE
    local LCL_UNIX_DISTRO

    # check the installed tools file was deleted
    if [ -f "$LCL_FULL_PATH_INSTALLED_FILE" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_FULL_PATH_INSTALLED_FILE was NOT deleted${NC}"
        return 1
    fi

    PrintTrace "$TRACE_INFO" "${GRN}[OK] Validation ${FUNCNAME[0]} for: $LCL_INSTALLATION_FILE${NC}"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


ValidateShellEnvironmentRemoved() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_TEST_SHELL_ENV="$1"

    # check the shell environment file was created
    if [ ! -f "$LCL_TEST_SHELL_ENV" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_TEST_SHELL_ENV not found${NC}"
        return 1
    fi


    if grep -Fq '# BEGIN >>>>>> DO_NOT_REMOVE >>>>>> ABK_ENV' "$LCL_TEST_SHELL_ENV"; then
        PrintTrace "$TRACE_ERROR" "${RED}[ERROR] ABK config is FOUND in $LCL_TEST_SHELL_ENV${NC}"
        cat "$LCL_TEST_SHELL_ENV"
        return 1
    fi

    PrintTrace "$TRACE_INFO" "${GRN}[OK] ${FUNCNAME[0]} for: $LCL_TEST_SHELL_ENV${NC}"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


ValidateLinksDeleted() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_LINKS_DIR="./unixBin/env"
    local LCL_LINKS_FILES=(
        "LINK_aws.env"
        "LINK_direnv.env"
        "LINK_nodenv.env"
        "LINK_oh-my-posh.env"
        "LINK_pyenv.env"
        "LINK_rbenv.env"
        "LINK_tfenv.env"
        "LINK_uv.env"
        "LINK_zsh_plugins.env"
    )

    # check the links were created
    (
        cd "$LCL_LINKS_DIR" || {
            PrintTrace "$TRACE_ERROR" "${RED}ERROR: Could not cd into $LCL_LINKS_DIR${NC}"
            exit 1
        }

        for LCL_LINK_FILE in "${LCL_LINKS_FILES[@]}"; do
            if [ -L "$LCL_LINK_FILE" ]; then
                PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_LINK_FILE was NOT deleted${NC}"
                exit 1
            fi
            PrintTrace "$TRACE_INFO" "${GRN}[OK] $LCL_LINK_FILE deleted${NC}"
        done
    ) || return 1

    PrintTrace "$TRACE_INFO" "${GRN}[OK] Validation  ${FUNCNAME[0]}${NC}"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


ValidateDirectoryEmpty() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_CHECK_DIR="$1"

    if [ ! -d "$LCL_CHECK_DIR" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_CHECK_DIR is not a directory or does not exist${NC}"
        return 1
    fi

    if [ !-z "$(ls -A "$LCL_CHECK_DIR")" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: Directory $LCL_CHECK_DIR is not empty.${NC}"
        return 1
    fi

    PrintTrace "$TRACE_INFO" "${GRN}[OK] Validated $LCL_CHECK_DIR is empty."
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


#---------------------------
# main
#---------------------------
echo ""
echo "-> $0 ($*)"


# shellcheck source=./unixBin/abkLib.sh
[ -f "$ABK_LIB_FILE" ] && . "$ABK_LIB_FILE" || PrintUsageAndExitWithCode 1 "${RED}ERROR: $ABK_LIB_FILE could not be found.${NC}"
export TRACE_LEVEL=$TRACE_INFO

# Is number of parameters ok
[ "$#" -ne 0 ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: wrong number of parameters${NC}"

# check Pre-Requisites
AbkLib_CheckPreRequisites || PrintUsageAndExitWithCode 1 "${RED}ERROR: cannot proceed Pre-Requisites are not met${NC}"


# check unixPackages directory
# [ ! -d "$UNIX_PACKAGES_DIR" ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: $UNIX_PACKAGES_DIR directory not found${NC}"
# PrintTrace "$TRACE_INFO" "${GRN}[OK] $UNIX_PACKAGES_DIR directory found${NC}"


# setup correct SHELL
ABK_SHELL="${SHELL##*/}"
[ "$ABK_SHELL" != "bash" ] && [ "$ABK_SHELL" != "zsh" ] && PrintTrace "$TRACE_ERROR" "${RED}ERROR: $ABK_SHELL is not supported. Please consider using bash or zsh${NC}" && exit 1


# Find test_*.json files in root directory
shopt -s nullglob
TEST_PACKAGE_FILES=(./test_*.json)
shopt -u nullglob
[ ${#TEST_PACKAGE_FILES[@]} -eq 0 ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: no test_*.json files found${NC}"


# test uninstall
PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${YLW}==> [TEST] Uninstall validation${NC}"
for TEST_PACKAGE_FILE in "${TEST_PACKAGE_FILES[@]}"; do
    PrintTrace "$TRACE_INFO" "${YLW}------------------------------------------------------------${NC}"
    PrintTrace "$TRACE_INFO" "${YLW}--> [TEST] Processing $TEST_PACKAGE_FILE${NC}"

    ./uninstall.sh "$TEST_PACKAGE_FILE" || PrintUsageAndExitWithCode 1 "${RED}ERROR: install.sh failed${NC}"
    ValidatePackageUninstall "$TEST_PACKAGE_FILE" || PrintUsageAndExitWithCode 1 "${RED}ERROR: Validation ValidatePackageUninstall failed for: $TEST_PACKAGE_FILE${NC}"
done


# test content has been removed from .zshrc/.bashrc
TEST_SHELL_ENV="${HOME}/.${ABK_SHELL}rc"
PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${YLW}==> [TEST] Validate content removed: $TEST_SHELL_ENV${NC}"
ValidateShellEnvironmentRemoved "$TEST_SHELL_ENV" || PrintUsageAndExitWithCode 1 "${RED}ERROR: ValidateShellEnvironmentRemoved failed for: $TEST_SHELL_ENV${NC}"


# test LINK files has been deleted
PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${YLW}==> [TEST] Validate: LINKs has been deleted${NC}"
ValidateLinksDeleted || PrintUsageAndExitWithCode 1 "${RED}ERROR: Validation of LINKs deletion failed${NC}"


PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
EMPTY_PACKAGE_DIR="unixPackages"
PrintTrace "$TRACE_INFO" "${YLW}==> [TEST] Validate: directory '$EMPTY_PACKAGE_DIR' is empty${NC}"
ValidateDirectoryEmpty "$EMPTY_PACKAGE_DIR" || PrintUsageAndExitWithCode $? "${RED}ERROR: Directory $EMPTY_PACKAGE_DIR is not empty${NC}"


PrintTrace "$TRACE_INFO" "${GRN}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${GRN}==> [OK] All validation tests passed${NC}"
PrintTrace "$TRACE_INFO" "${GRN}============================================================${NC}"

echo "<- $0 (0)"
exit 0
