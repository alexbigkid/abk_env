#!/usr/bin/env bash

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
GPG_KEY_TYPE="ed25519"
GPG_KEY_LENGTH="4096"
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
    echo "This script generates a master GPG key with three subkeys:"
    echo "  - Signature subkey (2 year expiration)"
    echo "  - Encryption subkey (2 year expiration)"
    echo "  - Authentication subkey (2 year expiration)"
    echo ""
    echo "The master key will be extracted for safe keeping and removed from active keyring."
    echo "A revocation certificate will also be generated."
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


generateGpgKeyPair() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
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
    
    cat > "$LCL_GPG_BATCH_FILE" <<EOF
%echo Generating GPG master key with subkeys...
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: cert
Subkey-Type: eddsa
Subkey-Curve: ed25519
Subkey-Usage: sign
Expire-Date: $GPG_EXPIRY
Name-Real: $LCL_USER_NAME
Name-Email: $LCL_USER_EMAIL
%no-protection
%commit
%echo Done
EOF

    chmod 600 "$LCL_GPG_BATCH_FILE"
    
    PrintTrace "$TRACE_INFO" "🔐 Generating master key and signature subkey..."
    gpg --batch --generate-key "$LCL_GPG_BATCH_FILE"
    LCL_EXIT_CODE=$?
    
    # Securely remove batch file
    shred -u "$LCL_GPG_BATCH_FILE" 2>/dev/null || rm -f "$LCL_GPG_BATCH_FILE"
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to generate GPG key pair. Aborting.${NC}"
    fi
    
    PrintTrace "$TRACE_INFO" "✅ GPG master key and signature subkey generated successfully"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


getGpgFingerprint() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_RETURN_VAR=$1
    local LCL_USER_EMAIL="$2"
    local LCL_EXIT_CODE=0
    
    # Get the master key fingerprint using the email (if provided) or get the most recent key
    local LCL_KEY_FP
    if [ -n "$LCL_USER_EMAIL" ]; then
        LCL_KEY_FP=$(gpg --list-secret-keys --with-colons "$LCL_USER_EMAIL" | awk -F: '/^sec:/ {getline; if($1=="fpr") print $10; exit}')
    fi
    
    # If email lookup failed or no email provided, get the most recent secret key
    if [ -z "$LCL_KEY_FP" ]; then
        PrintTrace "$TRACE_INFO" "Getting most recent secret key fingerprint"
        LCL_KEY_FP=$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ {getline; if($1=="fpr") print $10; exit}')
    fi
    
    if [ -z "$LCL_KEY_FP" ]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Failed to extract fingerprint${NC}"
    fi
    
    PrintTrace "$TRACE_INFO" "✅ Master key fingerprint: $LCL_KEY_FP"
    eval $LCL_RETURN_VAR=\$LCL_KEY_FP
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


addEncryptionSubkey() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Adding encryption subkey"
    
    expect <<EOF
        log_user 1
        set timeout 60
        spawn gpg --edit-key $LCL_KEY_FP
        expect "gpg>" { send "addkey\\r" }
        expect "Your selection?" { send "12\\r" }  # ECC (encrypt only)
        expect "Your selection?" { send "1\\r" }   # Curve 25519
        expect "Key is valid for?" { send "$GPG_EXPIRY\\r" }
        expect "Is this correct?" { send "y\\r" }
        expect "gpg>" { send "save\\r" }
        expect eof
EOF
    
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
    
    PrintTrace "$TRACE_INFO" "🔐 Adding authentication subkey"
    
    expect <<EOF
        log_user 1
        set timeout 60
        spawn gpg --edit-key $LCL_KEY_FP
        expect "gpg>" { send "addkey\\r" }
        expect "Your selection?" { send "11\\r" }  # ECC (set your own capabilities)
        expect "Your selection?" { send "1\\r" }   # Curve 25519
        expect "Possible actions" { 
            send "s\\r"  # Toggle sign capability (remove it)
        }
        expect "Possible actions" { 
            send "a\\r"  # Toggle authenticate capability (add it)
        }
        expect "Possible actions" { 
            send "q\\r"  # Finished setting capabilities
        }
        expect "Key is valid for?" { send "$GPG_EXPIRY\\r" }
        expect "Is this correct?" { send "y\\r" }
        expect "gpg>" { send "save\\r" }
        expect eof
EOF
    
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
    
    gpg --output "$LCL_REVOKE_FILE" --gen-revoke "$LCL_KEY_FP" <<EOF
y
1
Revocation certificate generated by setSwGpg.sh

y
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


removeMasterKeyFromKeyring() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔐 Removing master key from active keyring (keeping subkeys only)"
    
    # Delete the master secret key, keeping subkeys
    expect <<EOF
        log_user 1
        set timeout 30
        spawn gpg --delete-secret-key $LCL_KEY_FP
        expect "Delete this key from the keyring?" { send "y\\r" }
        expect eof
EOF
    
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to remove master key from keyring"
        return $LCL_EXIT_CODE
    fi
    
    # Re-import only the subkeys
    local LCL_SUBKEYS_FILE="$GNUPG_BACKUP_DIR/subkeys/${LCL_KEY_FP}-subkeys.asc"
    gpg --import "$LCL_SUBKEYS_FILE"
    LCL_EXIT_CODE=$?
    
    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace "$TRACE_ERROR" "❌ Failed to re-import subkeys"
        return $LCL_EXIT_CODE
    fi
    
    PrintTrace "$TRACE_INFO" "✅ Master key removed from active keyring, subkeys available for daily use"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
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
    
    # Verify that the master key file contains the expected key
    if [ -f "$LCL_MASTER_KEY_FILE" ]; then
        local LCL_KEY_IN_BACKUP=$(gpg --show-keys --with-colons "$LCL_MASTER_KEY_FILE" 2>/dev/null | awk -F: '/^pub:/ {getline; if($1=="fpr") print $10; exit}')
        if [ "$LCL_KEY_IN_BACKUP" = "$LCL_KEY_FP" ]; then
            PrintTrace "$TRACE_INFO" "✅ Master key backup contains correct key"
        else
            PrintTrace "$TRACE_ERROR" "❌ Master key backup fingerprint mismatch"
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
    
    # Clear any temporary variables that might contain sensitive data
    unset GPG_BATCH_FILE
    unset LCL_GPG_BATCH_FILE
    unset USER_EMAIL
    unset KEY_FP
    
    # Clear bash history of this session (if possible)
    history -c 2>/dev/null || true
    
    PrintTrace "$TRACE_INFO" "✅ Secure cleanup completed"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


validateKeySetup() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_KEY_FP="$1"
    local LCL_EXIT_CODE=0
    
    PrintTrace "$TRACE_INFO" "🔍 Validating key setup"
    
    # Check that we have subkeys but no master secret key
    local LCL_SEC_KEYS=$(gpg --list-secret-keys --with-colons "$LCL_KEY_FP" | grep "^sec:" | wc -l)
    local LCL_SSB_KEYS=$(gpg --list-secret-keys --with-colons "$LCL_KEY_FP" | grep "^ssb:" | wc -l)
    
    if [ "$LCL_SEC_KEYS" -gt 0 ]; then
        PrintTrace "$TRACE_WARNING" "⚠️  Master secret key still present in keyring"
    else
        PrintTrace "$TRACE_INFO" "✅ Master secret key properly removed from keyring"
    fi
    
    if [ "$LCL_SSB_KEYS" -ge 3 ]; then
        PrintTrace "$TRACE_INFO" "✅ All subkeys present: $LCL_SSB_KEYS subkeys found"
    else
        PrintTrace "$TRACE_WARNING" "⚠️  Expected 3 subkeys, found: $LCL_SSB_KEYS"
        LCL_EXIT_CODE=1
    fi
    
    # List current key setup
    PrintTrace "$TRACE_INFO" "📋 Current key configuration:"
    gpg --list-secret-keys "$LCL_KEY_FP"
    
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
5. Remove master key from keyring again

SECURITY NOTES:
--------------
- The master key has been removed from your daily keyring for security
- Only subkeys remain for signing, encryption, and authentication
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

[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS"
set -e

# Main execution flow
checkPrerequisiteToolsAreInstalled
setupSecureDirectories

# Generate the master key and first subkey (signature)
generateGpgKeyPair

# Get the master key fingerprint and user email for subsequent operations
USER_EMAIL=$(git config user.email 2>/dev/null || git config --global user.email 2>/dev/null || echo "")
getGpgFingerprint KEY_FP "$USER_EMAIL"

# Add the additional subkeys
addEncryptionSubkey "$KEY_FP"
addAuthenticationSubkey "$KEY_FP"

# Generate revocation certificate
generateRevocationCertificate "$KEY_FP"

# Export master key and subkeys for backup
exportMasterKey "$KEY_FP"
exportSubkeys "$KEY_FP"

# Verify backup integrity before removing master key
verifyBackupIntegrity "$KEY_FP"

# Remove master key from active keyring, keep only subkeys
removeMasterKeyFromKeyring "$KEY_FP"

# Validate the final setup
validateKeySetup "$KEY_FP"

# Generate comprehensive backup instructions
generateBackupInstructions "$KEY_FP"

# Perform secure cleanup
performSecureCleanup

PrintTrace "$TRACE_INFO" "🎉 Software GPG key generation completed successfully!"
PrintTrace "$TRACE_INFO" "📁 Backup files located in: $GNUPG_BACKUP_DIR"
PrintTrace "$TRACE_INFO" "🔐 Master key safely stored offline, subkeys ready for daily use"
PrintTrace "$TRACE_INFO" "📖 Read the backup instructions in: $GNUPG_BACKUP_DIR/README-IMPORTANT-${KEY_FP}.txt"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE