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


ValidatePackageInstall() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_INSTALLATION_FILE=$1
    local LCL_FULL_PATH_INSTALLED_FILE="$UNIX_PACKAGES_DIR/$LCL_INSTALLATION_FILE"
    local LCL_FULL_PATH_VALIDATION_FILE
    local LCL_UNIX_DISTRO
    local LCL_DISTRO_VERSION

    # check the installed tools file was created
    if [ ! -f "$LCL_FULL_PATH_INSTALLED_FILE" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_FULL_PATH_INSTALLED_FILE not found${NC}"
        return 1
    fi

    # get the unix version
    if [ "$ABK_UNIX_TYPE" == "linux" ]; then
        AbkLib_GetId_unix LCL_UNIX_DISTRO || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: AbkLib_GetId_unix failed${NC}"; return 1; }
        AbkLib_GetVersionId_linux LCL_DISTRO_VERSION || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: AbkLib_GetVersionId_linux failed${NC}"; return 1; }
        PrintTrace "$TRACE_INFO" "LCL_UNIX_DISTRO       = $LCL_UNIX_DISTRO"
        PrintTrace "$TRACE_INFO" "LCL_DISTRO_VERSION    = $LCL_DISTRO_VERSION"
        LCL_FULL_PATH_VALIDATION_FILE="tests/$ABK_UNIX_TYPE/$LCL_UNIX_DISTRO/$LCL_DISTRO_VERSION/$LCL_INSTALLATION_FILE"
    elif [ "$ABK_UNIX_TYPE" == "macOS" ]; then
        AbkLib_GetVersionId_macOS LCL_DISTRO_VERSION || { PrintTrace "$TRACE_ERROR" "${RED}ERROR: AbkLib_GetVersionId_macOS failed${NC}"; return 1; }
        PrintTrace "$TRACE_INFO" "LCL_DISTRO_VERSION    = $LCL_DISTRO_VERSION"
        LCL_FULL_PATH_VALIDATION_FILE="tests/macOS/$LCL_DISTRO_VERSION/$LCL_INSTALLATION_FILE"
    else
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: ABK_UNIX_TYPE = $ABK_UNIX_TYPE is not supported${NC}"
        return 1
    fi

    # check validation file exist
    if [ ! -f "$LCL_FULL_PATH_VALIDATION_FILE" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_FULL_PATH_VALIDATION_FILE not found${NC}"
        return 1
    fi

    # compare the contents of the installed file and the validation file
    if ! cmp -s "$LCL_FULL_PATH_INSTALLED_FILE" "$LCL_FULL_PATH_VALIDATION_FILE"; then
        PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_FULL_PATH_INSTALLED_FILE and $LCL_FULL_PATH_VALIDATION_FILE are different${NC}"
        diff "$LCL_FULL_PATH_INSTALLED_FILE" "$LCL_FULL_PATH_VALIDATION_FILE"
        PrintTrace "$TRACE_INFO" "${RED}Content of $LCL_FULL_PATH_INSTALLED_FILE ${NC}"
        cat "$LCL_FULL_PATH_INSTALLED_FILE"
        PrintTrace "$TRACE_INFO" "${RED}Content of $LCL_FULL_PATH_VALIDATION_FILE ${NC}"
        cat "$LCL_FULL_PATH_VALIDATION_FILE"
        PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
        return 1
    fi

    PrintTrace "$TRACE_INFO" "${GRN}[OK] Validation ${FUNCNAME[0]} for: $LCL_INSTALLATION_FILE${NC}"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


ValidateShellEnvironmentAdded() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_TEST_SHELL_ENV="$1"

    # check the shell environment file was created
    if [ ! -f "$LCL_TEST_SHELL_ENV" ]; then
        PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_TEST_SHELL_ENV not found${NC}"
        return 1
    fi


    local LCL_EXPECTED_CONTENT
    LCL_EXPECTED_CONTENT=$(cat <<'EOF'
# BEGIN >>>>>> DO_NOT_REMOVE >>>>>> ABK_ENV
if [ -f "$HOME/abk_env/./unixBin/env/abk.env" ]; then
    . "$HOME/abk_env/./unixBin/env/abk.env"
fi
# END <<<<<< DO_NOT_REMOVE <<<<<< ABK_ENV
EOF
)
    if ! grep -Fq "$LCL_EXPECTED_CONTENT" "$LCL_TEST_SHELL_ENV"; then
        PrintTrace "$TRACE_ERROR" "${RED}[ERROR] ABK config is NOT found in $LCL_TEST_SHELL_ENV${NC}"
        cat "$LCL_TEST_SHELL_ENV"
        return 1
    fi

    PrintTrace "$TRACE_INFO" "${GRN}[OK]  ${FUNCNAME[0]} for: $LCL_TEST_SHELL_ENV${NC}"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


ValidateLinksCreated() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_LINKS_DIR="./unixBin/env"
    local LCL_LINKS_FILES=(
        "LINK_direnv.env"
        "LINK_fzf.env"
        "LINK_nodenv.env"
        "LINK_oh-my-posh.env"
        "LINK_pyenv.env"
        "LINK_uv.env"
        "LINK_zsh_plugins.env"
    )

    (
        cd "$LCL_LINKS_DIR" || {
            PrintTrace "$TRACE_ERROR" "${RED}ERROR: Could not cd into $LCL_LINKS_DIR${NC}"
            exit 1
        }

        for LCL_LINK_FILE in "${LCL_LINKS_FILES[@]}"; do
            if [ -L "$LCL_LINK_FILE" ]; then
                local LCL_TARGET
                local LCL_XXX_TARGET
                LCL_TARGET=$(readlink "$LCL_LINK_FILE")
                LCL_XXX_TARGET="XXX_${LCL_LINK_FILE#LINK_}"

                if [ "$LCL_TARGET" == "$LCL_XXX_TARGET" ]; then
                    PrintTrace "$TRACE_INFO" "${GRN}[OK] $LCL_LINK_FILE points to $LCL_TARGET${NC}"
                else
                    PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_LINK_FILE points to $LCL_TARGET instead of $LCL_XXX_TARGET${NC}"
                    exit 1
                fi
            else
                PrintTrace "$TRACE_ERROR" "${RED}ERROR: $LCL_LINK_FILE not found${NC}"
                exit 1
            fi
        done
    ) || return 1

    PrintTrace "$TRACE_INFO" "${GRN}[OK] Validation  ${FUNCNAME[0]}${NC}"
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
[ "$#" -gt 1 ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: wrong number of parameters${NC}"

# check Pre-Requisites
AbkLib_CheckPreRequisites || PrintUsageAndExitWithCode 1 "${RED}ERROR: cannot proceed Pre-Requisites are not met${NC}"


# check unixPackages directory
# [ ! -d "$UNIX_PACKAGES_DIR" ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: $UNIX_PACKAGES_DIR directory not found${NC}"
# PrintTrace "$TRACE_INFO" "${GRN}[OK] $UNIX_PACKAGES_DIR directory found${NC}"


# setup correct SHELL
ABK_SHELL="${SHELL##*/}"
[ "$ABK_SHELL" != "bash" ] && [ "$ABK_SHELL" != "zsh" ] && PrintTrace "$TRACE_ERROR" "${RED}ERROR: $ABK_SHELL is not supported. Please consider using bash or zsh${NC}" && exit 1


# find all json installation files
shopt -s nullglob
FILE_PREFIX="${1:-tools_}"
TEST_PACKAGE_FILES=(./"${FILE_PREFIX}"*.json)
shopt -u nullglob
[ ${#TEST_PACKAGE_FILES[@]} -eq 0 ] && PrintUsageAndExitWithCode 1 "${RED}ERROR: no file with prefix found: ${FILE_PREFIX}${NC}"


# test install
PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${YLW}==> [TEST] Install validation${NC}"
for TEST_PACKAGE_FILE in "${TEST_PACKAGE_FILES[@]}"; do
    PrintTrace "$TRACE_INFO" "${YLW}------------------------------------------------------------${NC}"
    PrintTrace "$TRACE_INFO" "${YLW}--> [TEST] Processing $TEST_PACKAGE_FILE${NC}"

    ./install.sh "$TEST_PACKAGE_FILE" || PrintUsageAndExitWithCode 1 "${RED}ERROR: install.sh failed${NC}"
    ValidatePackageInstall "$TEST_PACKAGE_FILE" || PrintUsageAndExitWithCode 1 "${RED}ERROR: Validation ValidatePackageInstall failed for: $TEST_PACKAGE_FILE${NC}"
done


# test content has been added to .zshrc/.bashrc
PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
PrintTrace "$TRACE_DEBUG" "${YLW}==> SHELL        = $SHELL${NC}"
PrintTrace "$TRACE_DEBUG" "${YLW}==> ABK_SHELL    = $ABK_SHELL${NC}"
TEST_SHELL_ENV="${HOME}/.${ABK_SHELL}rc"
PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${YLW}==> [TEST] Validate content added: $TEST_SHELL_ENV${NC}"
ValidateShellEnvironmentAdded "$TEST_SHELL_ENV" || PrintUsageAndExitWithCode 1 "${RED}ERROR: Validation ValidateShellEnvironmentAdded failed for: $TEST_SHELL_ENV${NC}"


# test LINK files has been created
PrintTrace "$TRACE_INFO" "${YLW}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${YLW}==> [TEST] Validate: LINKs has been created${NC}"
ValidateLinksCreated || PrintUsageAndExitWithCode 1 "${RED}ERROR: Validation of LINKs creation failed${NC}"


PrintTrace "$TRACE_INFO" "${GRN}============================================================${NC}"
PrintTrace "$TRACE_INFO" "${GRN}==> [OK] All validation tests passed${NC}"
PrintTrace "$TRACE_INFO" "${GRN}============================================================${NC}"

echo "<- $0 (0)"
exit 0
