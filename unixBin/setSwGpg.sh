#!/usr/bin/env bash

#------------------------------------------------------------------------------
# setSwGpg.sh - create a software-only GPG key (no YubiKey)
#
# Generates a new GPG key that lives on this computer, with backups and
# recovery instructions in ~/.gnupg-backup/. No parameters.
#
# What it creates:
#   - Master key: Ed25519, certify-only, expires in 2y
#   - Subkeys (2y): sign (Ed25519), encrypt (Cv25519), auth (Ed25519, e.g. SSH)
#   - Identity: $GIT_USER_NAME/$GIT_USER_EMAIL if both set, else git
#     user.name/user.email (local repo config first, then global)
#   - ~/.gnupg-backup/ (mode 700), all named by key fingerprint:
#       master-key/<FP>-master-key.asc         master secret key
#       master-key/<FP>-master-key-public.asc  public key
#       subkeys/<FP>-subkeys.asc               subkeys for daily use
#       revocation/<FP>-revocation.asc         revocation certificate
#       README-IMPORTANT-<FP>.txt              backup/recovery/rotation steps
#
# Notes:
#   - NO passphrase on any key (by design). Anyone with these files can use
#     the key.
#   - The new key is found by its exact fingerprint, so existing keys with the
#     same email (e.g. a YubiKey key) are never touched.
#   - The master key is NOT removed from the keyring - do it manually once the
#     backups are safe (the script prints these with your fingerprint):
#       1. ls -laR ~/.gnupg-backup/                  verify backups
#       2. copy ~/.gnupg-backup to offline media      USB drive, paper
#       3. gpg --delete-secret-keys <FP>              removes master + subkeys
#       4. gpg --import ~/.gnupg-backup/subkeys/<FP>-subkeys.asc
#       5. gpg --list-secret-keys <FP>                master must show 'sec#'
#       6. rm -P ~/.gnupg-backup/master-key/<FP>-master-key.asc
#                                                     (Linux: shred -u)
#   - Does NOT configure git signing, gpg-agent or SSH to use the key.
#   - Requires: gpg, gpg-agent, expect
#------------------------------------------------------------------------------

#---------------------------
# variables definitions
#---------------------------
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=0
SCRIPT_NAME=$(basename $0)
SCRIPT_PATH=$(dirname $0)
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"
GNUPG_DIR="$HOME/.gnupg"
GNUPG_BACKUP_DIR="$HOME/.gnupg-backup"
GPG_EXPIRY="2y"


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode ()
{
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - generates software-only GPG keys with best practices"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo ""
    echo "This script generates a certify-only master GPG key (no passphrase) with three subkeys:"
    echo "  - Signature subkey (2 year expiration)"
    echo "  - Encryption subkey (2 year expiration)"
    echo "  - Authentication subkey (2 year expiration)"
    echo ""
    echo "Master key, subkeys and a revocation certificate are exported to $GNUPG_BACKUP_DIR."
    echo "The master key is NOT removed from the keyring - the script prints the manual steps."
    echo ""
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo $2
    exit $1
}


checkPrerequisiteToolsAreInstalled () {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    if [ "$ABK_UNIX_TYPE" = "macOS" ]; then
        declare -a required_tools=(gpg gpg-agent expect)
    elif [ "$ABK_UNIX_TYPE" = "linux" ]; then
        declare -a required_tools=(gpg gpg-agent expect)
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Unknown OS type: $ABK_UNIX_TYPE${NC}"
    fi

    for tool in "${required_tools[@]}"; do
      if ! command -v "$tool" &>/dev/null; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Required tool '$tool' is not installed. Please install: $tool. Aborting.${NC}"
      fi
    done
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setupSecureDirectories() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Setting up secure directories"
    
    # Ensure .gnupg directory exists with proper permissions
    mkdir -p "$GNUPG_DIR"
    chmod 700 "$GNUPG_DIR"
    
    # Create backup directory for master key storage
    mkdir -p "$GNUPG_BACKUP_DIR"
    chmod 700 "$GNUPG_BACKUP_DIR"
    
    # Create subdirectories for organized storage
    mkdir -p "$GNUPG_BACKUP_DIR/master-key"
    mkdir -p "$GNUPG_BACKUP_DIR/revocation"
    mkdir -p "$GNUPG_BACKUP_DIR/subkeys"
    
    chmod 700 "$GNUPG_BACKUP_DIR/master-key"
    chmod 700 "$GNUPG_BACKUP_DIR/revocation"
    chmod 700 "$GNUPG_BACKUP_DIR/subkeys"
    
    PrintTrace "$TRACE_INFO" "✅ Secure directories created"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


# Generates the master key and returns its fingerprint in the variable named by $1.
generateGpgKeyPair() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Generating GPG key pair with Ed25519 algorithm"
    
    # Get user information
    local LCL_USER_NAME
    local LCL_USER_EMAIL
    
    # Check for environment variables first
    if [ -n "$GIT_USER_NAME" ] && [ -n "$GIT_USER_EMAIL" ]; then
        LCL_USER_NAME="$GIT_USER_NAME"
        LCL_USER_EMAIL="$GIT_USER_EMAIL"
        PrintTrace "$TRACE_INFO" "Using environment variables: $LCL_USER_NAME <$LCL_USER_EMAIL>"
    else
        # Try local Git config first, then fallback to global
        LCL_USER_NAME=$(git config user.name 2>/dev/null || git config --global user.name 2>/dev/null || echo "")
        LCL_USER_EMAIL=$(git config user.email 2>/dev/null || git config --global user.email 2>/dev/null || echo "")
        
        if [ -z "$LCL_USER_NAME" ] || [ -z "$LCL_USER_EMAIL" ]; then
            PrintUsageAndExitWithCode 1 "${RED}❌ Git user.name and user.email must be configured.${NC}
${RED}Configure locally: git config user.name \"Your Name\" && git config user.email \"your.email@example.com\"${NC}
${RED}Or globally: git config --global user.name \"Your Name\" && git config --global user.email \"your.email@example.com\"${NC}"
        fi
        
        # Determine which config was used for logging
        local LCL_LOCAL_NAME=$(git config user.name 2>/dev/null || echo "")
        local LCL_LOCAL_EMAIL=$(git config user.email 2>/dev/null || echo "")
        
        if [ -n "$LCL_LOCAL_NAME" ] && [ -n "$LCL_LOCAL_EMAIL" ]; then
            PrintTrace "$TRACE_INFO" "Using local Git repository configuration: $LCL_USER_NAME <$LCL_USER_EMAIL>"
        else
            PrintTrace "$TRACE_INFO" "Using global Git configuration: $LCL_USER_NAME <$LCL_USER_EMAIL>"
        fi
    fi
    
    # Create GPG batch configuration for automated key generation
    local LCL_GPG_BATCH_FILE="$GNUPG_DIR/gpg-batch-config.tmp"
    local LCL_GPG_STATUS_FILE="$GNUPG_DIR/gpg-status.tmp"
    
    # Create the batch file line by line to avoid any hidden characters
    echo "Key-Type: eddsa" > "$LCL_GPG_BATCH_FILE"
    echo "Key-Curve: ed25519" >> "$LCL_GPG_BATCH_FILE"
    echo "Key-Usage: cert" >> "$LCL_GPG_BATCH_FILE"
    echo "Expire-Date: $GPG_EXPIRY" >> "$LCL_GPG_BATCH_FILE"
    echo "Name-Real: $LCL_USER_NAME" >> "$LCL_GPG_BATCH_FILE"
    echo "Name-Email: $LCL_USER_EMAIL" >> "$LCL_GPG_BATCH_FILE"
    echo "%no-protection" >> "$LCL_GPG_BATCH_FILE"
    echo "%commit" >> "$LCL_GPG_BATCH_FILE"

    chmod 600 "$LCL_GPG_BATCH_FILE"
    
    # PrintTrace "$TRACE_DEBUG" "📋 Batch file contents:"
    # cat -n "$LCL_GPG_BATCH_FILE" >&2
    
    PrintTrace "$TRACE_INFO" "🔐 Generating certify-only master key..."
    gpg --batch --status-file "$LCL_GPG_STATUS_FILE" --generate-key "$LCL_GPG_BATCH_FILE" || LCL_EXIT_CODE=$?

    # Securely remove batch file
    shred -u "$LCL_GPG_BATCH_FILE" 2>/dev/null || rm -f "$LCL_GPG_BATCH_FILE"

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        rm -f "$LCL_GPG_STATUS_FILE"
        PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to generate GPG master key. Aborting.${NC}"
    fi

    # Take the fingerprint of the key just created from gpg's status output
    # ("[GNUPG:] KEY_CREATED P <fingerprint>"), so an existing key with the
    # same email (e.g. a YubiKey key) can never be picked by mistake.
    local LCL_KEY_FP
    LCL_KEY_FP=$(awk '$2 == "KEY_CREATED" {print $4; exit}' "$LCL_GPG_STATUS_FILE")
    rm -f "$LCL_GPG_STATUS_FILE"

    if [ -z "$LCL_KEY_FP" ]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Failed to read fingerprint of the new key. Aborting.${NC}"
    fi

    PrintTrace "$TRACE_INFO" "✅ GPG master key generated, fingerprint: $LCL_KEY_FP"
    eval "$LCL_RETURN_VAR=\$LCL_KEY_FP"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


addEncryptionSubkey() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Adding encryption subkey using gpg --quick-add-key"
    gpg --batch --pinentry-mode loopback --passphrase "" --quick-add-key "$LCL_KEY_FP" cv25519 encr "$GPG_EXPIRY"
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to add encryption subkey"
    else
        PrintTrace "$TRACE_INFO" "✅ Encryption subkey added successfully"
    fi
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


addAuthenticationSubkey() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Adding authentication subkey using gpg --quick-add-key"
    gpg --batch --pinentry-mode loopback --passphrase "" --quick-add-key "$LCL_KEY_FP" ed25519 auth "$GPG_EXPIRY"
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to add authentication subkey"
    else
        PrintTrace "$TRACE_INFO" "✅ Authentication subkey added successfully"
    fi
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


generateRevocationCertificate() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Generating revocation certificate"
    
    local LCL_REVOKE_FILE="$GNUPG_BACKUP_DIR/revocation/${LCL_KEY_FP}-revocation.asc"
    
    # Use expect for revocation certificate since --batch doesn't work with --gen-revoke
    expect <<EOF
        log_user 0
        set timeout 30
        spawn gpg --output "$LCL_REVOKE_FILE" --gen-revoke "$LCL_KEY_FP"
        expect "Create a revocation certificate for this key?" { send "y\\r" }
        expect "Your decision?" { send "0\\r" }
        expect "Enter an optional description" { send "\\r" }
        expect "Is this okay?" { send "y\\r" }
        expect eof
EOF
    
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -eq 0 ]; then
        chmod 600 "$LCL_REVOKE_FILE"
        PrintTrace "$TRACE_INFO" "✅ Revocation certificate saved to: $LCL_REVOKE_FILE"
    else
        PrintTrace "$TRACE_ERROR" "❌ Failed to generate revocation certificate"
    fi
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


exportMasterKey() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Exporting master key for offline storage"
    
    local LCL_MASTER_KEY_FILE="$GNUPG_BACKUP_DIR/master-key/${LCL_KEY_FP}-master-key.asc"
    local LCL_MASTER_KEY_PUB_FILE="$GNUPG_BACKUP_DIR/master-key/${LCL_KEY_FP}-master-key-public.asc"
    
    # Export secret master key
    gpg --export-secret-keys --armor "$LCL_KEY_FP" > "$LCL_MASTER_KEY_FILE"
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to export master secret key"
        return $LCL_EXIT_CODE
    fi
    
    # Export public key
    gpg --export --armor "$LCL_KEY_FP" > "$LCL_MASTER_KEY_PUB_FILE"
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to export master public key"
        return $LCL_EXIT_CODE
    fi
    
    # Set secure permissions
    chmod 600 "$LCL_MASTER_KEY_FILE"
    chmod 600 "$LCL_MASTER_KEY_PUB_FILE"
    
    PrintTrace "$TRACE_INFO" "✅ Master keys exported to:"
    PrintTrace "$TRACE_INFO" "  Secret: $LCL_MASTER_KEY_FILE"
    PrintTrace "$TRACE_INFO" "  Public: $LCL_MASTER_KEY_PUB_FILE"
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


exportSubkeys() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Exporting subkeys"
    
    local LCL_SUBKEYS_FILE="$GNUPG_BACKUP_DIR/subkeys/${LCL_KEY_FP}-subkeys.asc"
    
    # Export subkeys only (without master key)
    gpg --export-secret-subkeys --armor "$LCL_KEY_FP" > "$LCL_SUBKEYS_FILE"
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to export subkeys"
        return $LCL_EXIT_CODE
    fi
    
    chmod 600 "$LCL_SUBKEYS_FILE"
    PrintTrace "$TRACE_INFO" "✅ Subkeys exported to: $LCL_SUBKEYS_FILE"
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


# The master key is intentionally NOT removed by this script. This only prints
# the manual steps to do it once the backups are confirmed.
printMasterKeyRemovalSteps() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"

    PrintTrace "$TRACE_INFO" "⚠️  The master secret key is STILL in your keyring and in $GNUPG_BACKUP_DIR (no passphrase)."
    PrintTrace "$TRACE_INFO" "🔐 To keep only the subkeys on this machine, do these steps manually:"
    PrintTrace "$TRACE_INFO" "   1. Verify backups:          ls -laR $GNUPG_BACKUP_DIR/"
    PrintTrace "$TRACE_INFO" "   2. Copy backups offline:    copy $GNUPG_BACKUP_DIR to offline media (USB drive, paper)"
    PrintTrace "$TRACE_INFO" "   3. Delete all secret keys:  gpg --delete-secret-keys $LCL_KEY_FP"
    PrintTrace "$TRACE_INFO" "   4. Re-import subkeys only:  gpg --import $GNUPG_BACKUP_DIR/subkeys/${LCL_KEY_FP}-subkeys.asc"
    PrintTrace "$TRACE_INFO" "   5. Check result:            gpg --list-secret-keys $LCL_KEY_FP   (master must show as 'sec#')"
    PrintTrace "$TRACE_INFO" "   6. Remove master from disk: rm -P $GNUPG_BACKUP_DIR/master-key/${LCL_KEY_FP}-master-key.asc  (Linux: shred -u)"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return 0
}


verifyBackupIntegrity() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔍 Verifying backup file integrity"
    
    local LCL_MASTER_KEY_FILE="$GNUPG_BACKUP_DIR/master-key/${LCL_KEY_FP}-master-key.asc"
    local LCL_MASTER_KEY_PUB_FILE="$GNUPG_BACKUP_DIR/master-key/${LCL_KEY_FP}-master-key-public.asc"
    local LCL_SUBKEYS_FILE="$GNUPG_BACKUP_DIR/subkeys/${LCL_KEY_FP}-subkeys.asc"
    local LCL_REVOKE_FILE="$GNUPG_BACKUP_DIR/revocation/${LCL_KEY_FP}-revocation.asc"
    
    # Check that all expected files exist and are not empty
    local files_to_check=("$LCL_MASTER_KEY_FILE" "$LCL_MASTER_KEY_PUB_FILE" "$LCL_SUBKEYS_FILE" "$LCL_REVOKE_FILE")
    for file in "${files_to_check[@]}"; do
        if [ ! -f "$file" ]; then
            PrintTrace "$TRACE_ERROR" "❌ Missing backup file: $file"
            LCL_EXIT_CODE=1
        elif [ ! -s "$file" ]; then
            PrintTrace "$TRACE_ERROR" "❌ Empty backup file: $file"
            LCL_EXIT_CODE=1
        else
            PrintTrace "$TRACE_INFO" "✅ Backup file verified: $(basename "$file")"
        fi
    done
    
    # Verify that the master key file contains a valid key
    if [ -f "$LCL_MASTER_KEY_FILE" ]; then
        if gpg --show-keys "$LCL_MASTER_KEY_FILE" >/dev/null 2>&1; then
            PrintTrace "$TRACE_INFO" "✅ Master key backup is valid"
        else
            PrintTrace "$TRACE_ERROR" "❌ Master key backup is invalid"
            LCL_EXIT_CODE=1
        fi
    fi
    
    if [ $LCL_EXIT_CODE -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "✅ All backup files verified successfully"
    else
        PrintTrace "$TRACE_ERROR" "❌ Backup verification failed"
    fi
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


performSecureCleanup() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🧹 Performing secure cleanup"
    
    # Find and securely remove any temporary GPG files
    find "$GNUPG_DIR" -name "*.tmp" -type f 2>/dev/null | while read -r temp_file; do
        if [ -f "$temp_file" ]; then
            PrintTrace "$TRACE_INFO" "🗑️  Securely removing: $temp_file"
            shred -u "$temp_file" 2>/dev/null || rm -f "$temp_file"
        fi
    done
    
    PrintTrace "$TRACE_INFO" "✅ Secure cleanup completed"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


validateKeySetup() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔍 Validating key setup"
    
    # Count subkeys
    local LCL_SSB_COUNT
    LCL_SSB_COUNT=$(gpg --list-secret-keys --with-colons "$LCL_KEY_FP" 2>/dev/null | grep -c "^ssb:" || true)
    
    if [ "$LCL_SSB_COUNT" -eq 3 ]; then
        PrintTrace "$TRACE_INFO" "✅ All 3 subkeys present: Sign, Encrypt, Auth"
    else
        PrintTrace "$TRACE_INFO" "⚠️  Expected 3 subkeys (S, E, A), found: $LCL_SSB_COUNT"
        LCL_EXIT_CODE=1
    fi
    
    # Check if master key backup exists
    local LCL_MASTER_KEY_FILE="$GNUPG_BACKUP_DIR/master-key/${LCL_KEY_FP}-master-key.asc"
    if [ -f "$LCL_MASTER_KEY_FILE" ]; then
        PrintTrace "$TRACE_INFO" "✅ Master key backup exists (move it to offline media)"
    else
        PrintTrace "$TRACE_INFO" "⚠️  Master key backup not found"
        LCL_EXIT_CODE=1
    fi
    
    # List current key setup
    PrintTrace "$TRACE_INFO" "📋 Current key configuration:"
    gpg --list-secret-keys "$LCL_KEY_FP" 2>/dev/null
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


generateBackupInstructions() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "📝 Generating backup and recovery instructions"
    
    local LCL_INSTRUCTIONS_FILE="$GNUPG_BACKUP_DIR/README-IMPORTANT-${LCL_KEY_FP}.txt"
    
    cat > "$LCL_INSTRUCTIONS_FILE" <<EOF
GPG KEY BACKUP AND RECOVERY INSTRUCTIONS
=======================================
Generated on: $(date)
Key Fingerprint: $LCL_KEY_FP

IMPORTANT FILES:
---------------
master-key/${LCL_KEY_FP}-master-key.asc       - Master secret key (KEEP SECURE!)
master-key/${LCL_KEY_FP}-master-key-public.asc - Master public key
subkeys/${LCL_KEY_FP}-subkeys.asc              - Subkeys for daily use
revocation/${LCL_KEY_FP}-revocation.asc        - Revocation certificate

BACKUP STORAGE:
--------------
1. Store the master-key files on offline media (USB drive, paper backup)
2. Store copies in multiple secure locations (safety deposit box, fireproof safe)
3. Store the revocation certificate separately from the master key
4. Keep the subkeys file as a backup for your daily-use keyring

RECOVERY PROCEDURES:
-------------------
To restore subkeys for daily use:
    gpg --import ${LCL_KEY_FP}-subkeys.asc

To restore full master key (for key management):
    gpg --import ${LCL_KEY_FP}-master-key.asc

To revoke the key in case of compromise:
    gpg --import ${LCL_KEY_FP}-revocation.asc

KEY ROTATION:
------------
Keys expire in 2 years. Before expiration:
1. Import master key temporarily
2. Extend expiration dates: gpg --edit-key $LCL_KEY_FP
3. Use 'expire' command for each key
4. Export updated subkeys
5. Remove master key from keyring again (see steps below)

REMOVING THE MASTER KEY FROM THIS MACHINE (manual - NOT done by setSwGpg.sh):
------------------------------------------------------------------------
The master secret key is still in your keyring and in master-key/ without a
passphrase. Once the backups are confirmed:
1. Verify backups:          ls -laR $GNUPG_BACKUP_DIR/
2. Copy backups offline:    copy $GNUPG_BACKUP_DIR to offline media (USB drive, paper)
3. Delete all secret keys:  gpg --delete-secret-keys $LCL_KEY_FP
4. Re-import subkeys only:  gpg --import $GNUPG_BACKUP_DIR/subkeys/${LCL_KEY_FP}-subkeys.asc
5. Check result:            gpg --list-secret-keys $LCL_KEY_FP
                            (master must show as 'sec#' = secret part not present)
6. Remove master from disk: rm -P $GNUPG_BACKUP_DIR/master-key/${LCL_KEY_FP}-master-key.asc
                            (Linux: shred -u ...)

SECURITY NOTES:
--------------
- Keys have NO passphrase - anyone with these files can use them
- Until the steps above are done, the master key is on this machine
- Never store the master key on a networked computer
- Regularly test your backup recovery procedures

Generated by: setSwGpg.sh
EOF

    chmod 600 "$LCL_INSTRUCTIONS_FILE"
    PrintTrace "$TRACE_INFO" "✅ Instructions saved to: $LCL_INSTRUCTIONS_FILE"
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


#---------------------------
# main
#---------------------------
if [ -f $ABK_LIB_FILE ]; then
    source $ABK_LIB_FILE
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

[ "$#" -eq 1 ] && [ "$1" == "--help" ] && PrintUsageAndExitWithCode 0
[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS"
set -e

# Main execution flow
checkPrerequisiteToolsAreInstalled
setupSecureDirectories

# Generate the certify-only master key and get its exact fingerprint
generateGpgKeyPair KEY_FP

# Add all three subkeys (since batch only created master key)
PrintTrace "$TRACE_INFO" "🔐 Adding signing subkey"
gpg --batch --pinentry-mode loopback --passphrase "" --quick-add-key "$KEY_FP" ed25519 sign "$GPG_EXPIRY"

addEncryptionSubkey "$KEY_FP"
addAuthenticationSubkey "$KEY_FP"

# Generate revocation certificate
generateRevocationCertificate "$KEY_FP"

# Export master key and subkeys for backup
exportMasterKey "$KEY_FP"
exportSubkeys "$KEY_FP"

# Verify backup integrity before removing master key
verifyBackupIntegrity "$KEY_FP"

# Master key is NOT removed - print the manual steps instead
printMasterKeyRemovalSteps "$KEY_FP"

# Validate the final setup
validateKeySetup "$KEY_FP"

# Generate comprehensive backup instructions
generateBackupInstructions "$KEY_FP"

# Perform secure cleanup
performSecureCleanup

PrintTrace "$TRACE_INFO" "🎉 Software GPG key generation completed successfully!"
PrintTrace "$TRACE_INFO" "📁 Backup files located in: $GNUPG_BACKUP_DIR"
PrintTrace "$TRACE_INFO" "🔐 Subkeys ready for daily use. Master key is still on this machine - see removal steps above"
PrintTrace "$TRACE_INFO" "📖 Read the backup instructions in: $GNUPG_BACKUP_DIR/README-IMPORTANT-${KEY_FP}.txt"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE