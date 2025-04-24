#!/usr/bin/env bash

#---------------------------
# variables definitions
#---------------------------
TRACE_LEVEL=5
EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMETERS=1
SCRIPT_NAME=$(basename $0)
SCRIPT_PATH=$(dirname $0)
ABK_LIB_FILE="$SCRIPT_PATH/abkLib.sh"


#---------------------------
# functions
#---------------------------
PrintUsageAndExitWithCode () {
    echo "-> PrintUsageAndExitWithCode"
    echo "$0 - creates GPG keys, backs them up and stores them on yubi key"
    echo "  Following tools needs to be installed: gpg, gpg-agent, yq"
    echo "  YoubiKey must be inserted and detected"
    echo "usage: $0"
    echo "  $0 --help   - display this info"
    echo "  $0 <yaml file> - creates GPG keys from the specified yaml file"
    echo "<- PrintUsageAndExitWithCode ($1)"
    echo
    echo -e $2
    exit $1
}


checkPrerequisiteToolsAreInstalled () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    declare -a required_tools=(gpg gpg-agent yq ykman)
    for tool in "${required_tools[@]}"; do
      if ! command -v "$tool" &>/dev/null; then
        PrintUsageAndExitWithCode 1 "❌ Required tool '$tool' is not installed. Aborting."
      fi
    done
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


checkYubiKeyPresence () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0
    PrintTrace $TRACE_INFO "🔍 Checking for YubiKey..."
    if ! gpg --card-status &>/dev/null; then
        PrintUsageAndExitWithCode 1 "${RED}❌ YubiKey not detected. Please insert your YubiKey and try again.${NC}"
    fi
    PrintTrace $TRACE_INFO "✅ YubiKey detected."
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


parseConfigFile () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_CONFIG_FILE=$2
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_INFO "📄  Parsing config file..."
    if [[ ! -f "$LCL_CONFIG_FILE" ]]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Config file '$LCL_CONFIG_FILE' not found.${NC}"
    fi

    eval $LCL_RETURN_VAR=\$LCL_CONFIG_FILE
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_CONFIG_FILE)"
    return $LCL_EXIT_CODE
}


createMasterGpgKey () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_CONFIG_FILE=$2
    local LCL_EXIT_CODE=0

    first_name=$(yq '.first_name' "$LCL_CONFIG_FILE")
    last_name=$(yq '.last_name' "$LCL_CONFIG_FILE")
    email=$(yq '.email' "$LCL_CONFIG_FILE")
    key_type=$(yq '.key_type // "ed25519"' "$LCL_CONFIG_FILE")
    curve=$(yq '.curve // "ed25519"' "$LCL_CONFIG_FILE")
    expiration=$(yq '.expiration // "0"' "$LCL_CONFIG_FILE")

    gpg --list-keys "$email" &>/dev/null && PrintUsageAndExitWithCode 1 "${RED}❌ Key for $email already exists. Please remove it first.${NC}"

    # ---------------------------
    # Generate key params file for batch input
    # ---------------------------
    PrintTrace $TRACE_INFO "🛠  Generating key parameters..."
    KEY_PARAM_FILE=$(mktemp)

    cat > "$KEY_PARAM_FILE" <<EOF
Key-Type: $key_type
Key-Curve: $curve
Key-Usage: cert
Name-Real: $first_name $last_name
Name-Email: $email
Expire-Date: $expiration
%commit
EOF

    PrintTrace $TRACE_INFO "🛠  Generating master key..."
    # gpg --batch --gen-key "$KEY_PARAM_FILE"
    gpg --batch --pinentry-mode loopback --passphrase "" --gen-key "$KEY_PARAM_FILE"
    rm "$KEY_PARAM_FILE"

    local LCL_FINGERPRINT=$(gpg --list-secret-keys --with-colons "$email" | awk -F: '/^fpr:/ {print $10; exit}')
    PrintTrace $TRACE_INFO "🔑  Fingerprint: $LCL_FINGERPRINT"

    eval $LCL_RETURN_VAR=\$LCL_FINGERPRINT
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_FINGERPRINT)"
    return $LCL_EXIT_CODE
}


createGpgSubKeys () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_CONFIG_FILE=$1
    local LCL_FINGER_PRINT=$2
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_INFO "🔑  Creating subkeys..."
    yq -o=json '.subkeys' "$LCL_CONFIG_FILE" | jq -c '.[]' | while IFS= read -r subkey; do
        PrintTrace $TRACE_INFO "abk:001: subkey = $subkey"
        usage=$(echo "$subkey" | jq -r '.usage')
        PrintTrace $TRACE_INFO "abk:002: usage = $usage"
        algo=$(echo "$subkey" | jq -r '.algo')
        PrintTrace $TRACE_INFO "abk:003: algo = $algo"
        expiration=$(echo "$subkey" | jq -r '.expiration // "0"')
        PrintTrace $TRACE_INFO "abk:005: expiration = $expiration"

        PrintTrace $TRACE_INFO "➕ Adding $usage subkey..."
        PrintTrace $TRACE_INFO "gpg --batch --pinentry-mode loopback --passphrase "" --quick-add-key $LCL_FINGER_PRINT $algo $usage $expiration"
        gpg --batch --pinentry-mode loopback --passphrase "" --quick-add-key "$LCL_FINGER_PRINT" "$algo" "$usage" "$expiration"
    done
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setupBackupDir () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_RETURN_VAR=$1
    local LCL_CONFIG_FILE=$2
    local LCL_EXIT_CODE=0

    local LCL_CONFIG_NAME=$(basename "$LCL_CONFIG_FILE" .yaml)
    PrintTrace $TRACE_INFO "📂  Setting up backup directory..."
    GNUPG_DIR="$HOME/.gnupg"
    BACKUP_DIR="$GNUPG_DIR/backup/$LCL_CONFIG_NAME"
    mkdir -p "$BACKUP_DIR"

    eval $LCL_RETURN_VAR=\$BACKUP_DIR
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($BACKUP_DIR)"
    return $LCL_EXIT_CODE
}


createGpgRevocationKey () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_BACKUP_DIR=$1
    local LCL_FINGER_PRINT=$2
    local LCL_REVOCATION_KEY=$3
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_INFO "📝  Creating revocation certificate..."

    expect <<EOF
        log_user 1
        spawn gpg --output "$LCL_BACKUP_DIR/$LCL_REVOCATION_KEY" --gen-revoke "$LCL_FINGER_PRINT"
        expect {
            "Create a revocation certificate for this key?" { send "y\r"; exp_continue }
            "Your decision?" { send "0\r"; exp_continue }
            "Enter an optional description" { send "Generic Revocation Key\r\r"; exp_continue }
            "Is this okay?" { send "y\r"; exp_continue }
            eof
        }
EOF

    [ $? -ne 0 ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to create revocation certificate.${NC}"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


backupMasterSecretGpgKey () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"
    local LCL_BACKUP_DIR=$1
    local LCL_FINGER_PRINT=$2
    local LCL_SEC_MASTER_KEY=$3
    local LCL_EXIT_CODE=0

    gpg --export-secret-key --armor --output "$LCL_BACKUP_DIR/$LCL_SEC_MASTER_KEY" "$LCL_FINGER_PRINT"
    [ $? -ne 0 ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to export secret master key.${NC}"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


backupMasterPublicGpgKey () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"
    local LCL_BACKUP_DIR=$1
    local LCL_FINGER_PRINT=$2
    local LCL_PUB_MASTER_KEY=$3
    local LCL_EXIT_CODE=0

    gpg --export --armor --output "$LCL_BACKUP_DIR/$LCL_PUB_MASTER_KEY" "$LCL_FINGER_PRINT"
    [ $? -ne 0 ] && PrintUsageAndExitWithCode 1 "${RED}❌ Failed to export public master key.${NC}"

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


backupGpgSubkeys () {
    local LCL_BACKUP_DIR="$1"
    local LCL_FINGER_PRINT="$2"
    local LCL_PREFIX="$3"
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    mkdir -p "$LCL_BACKUP_DIR"

    PrintTrace $TRACE_INFO "📋 Getting subkey IDs and usage types for $LCL_FINGER_PRINT"

    gpg --with-colons --list-secret-keys "$LCL_FINGER_PRINT" | awk -F: '
        $1 == "ssb" {
            split($12, usage, "");
            print $5, usage[1];
        }
    ' | while read -r SUBKEY_ID USAGE_CODE; do
        local SUFFIX
        case "$USAGE_CODE" in
            s) SUFFIX="s" ;;
            e) SUFFIX="e" ;;
            a) SUFFIX="a" ;;
            *) SUFFIX="unknown" ;;
        esac

        local OUTPUT_FILE="$LCL_BACKUP_DIR/${LCL_PREFIX}.sub.${SUFFIX}.sec.asc"
        PrintTrace $TRACE_INFO "💾 Backing up subkey $SUBKEY_ID as $OUTPUT_FILE"

        gpg --batch --yes --export-secret-subkeys --armor --output "$OUTPUT_FILE" "$SUBKEY_ID"
        if [ $? -ne 0 ]; then
            PrintUsageAndExitWithCode 1 "${RED}⚠️ Failed to export subkey $SUBKEY_ID${NC}"
        fi
    done

    PrintTrace $TRACE_INFO "✅ Subkey backups written to $LCL_BACKUP_DIR"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


resetYubiKeyPgpApplet () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"
    PrintTrace $TRACE_INFO "🔐  Checking the keys on YubiKey..."
    gpg --card-status

    PrintTrace $TRACE_CRITICAL "⚠️ This will overwrite existing keys on the YubiKey. Continue? (y/n)"
    read -r CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Operation cancelled.${NC}"
    fi

    PrintTrace $TRACE_INFO "📝  Resetting YubiKey OpenPGP Applet using ykman..."
    ykman openpgp reset --force
    local LCL_EXIT_CODE=$?

    [ $LCL_EXIT_CODE -ne 0 ] && PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to reset YubiKey OpenPGP Applet.${NC}"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setYubiKeyResetCode () {
    local ADMIN_PIN="12345678"
    local RESET_CODE="12345678"
    local LCL_EXIT_CODE=0

    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"
    PrintTrace $TRACE_INFO "🔐 Setting YubiKey OpenPGP Reset Code..."

    expect <<EOF
        log_user 1
        set timeout 60
        spawn gpg --card-edit
        expect "gpg/card>" { send "admin\r" }
        expect "gpg/card>" { send "passwd\r" }
        expect "Your selection?" { send "4\r" }
        expect "Admin PIN" { send "$ADMIN_PIN\r" }
        expect "Reset Code" { send "$RESET_CODE\r" }
        expect "Reset Code" { send "$RESET_CODE\r" }
        expect "Your selection?" { send "Q\r" }

        expect {
            "gpg/card>" { send "quit\r" }
            timeout { puts "❌ Timeout while setting Reset Code"; exit 1 }
        }
        expect eof
EOF
    local LCL_EXIT_CODE=$?

    [ $LCL_EXIT_CODE -ne 0 ] && PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to set YubiKey Reset Code.${NC}"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}

storeGpgSubKeysOnYubiKey () {
    local LCL_FINGER_PRINT="$1"

    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"
    PrintTrace $TRACE_INFO "🔐 Moving subkeys to YubiKey for $LCL_FINGER_PRINT"

    expect <<EOF
        log_user 1
        set timeout 60
        spawn gpg --edit-key "$LCL_FINGER_PRINT"

        # Select signing subkey (S)
        expect "gpg>" { send "key 1\r" }
        expect "gpg>" { send "keytocard\r" }
        expect "Your selection?" { send "1\r" }
        expect "Admin PIN" { send "12345678\r" }
        expect "gpg>" { send "key 1\r" } ;# Deselect

        # Select encryption subkey (E)
        expect "gpg>" { send "key 2\r" }
        expect "gpg>" { send "keytocard\r" }
        expect "Your selection?" { send "2\r" }
        expect "Admin PIN" { send "12345678\r" }
        expect "gpg>" { send "key 2\r" } ;# Deselect

        # Select authentication subkey (A)
        expect "gpg>" { send "key 3\r" }
        expect "gpg>" { send "keytocard\r" }
        expect "Your selection?" { send "3\r" }
        expect "Admin PIN" { send "12345678\r" }
        expect "gpg>" { send "key 3\r" } ;# Deselect

        # Save changes
        expect {
            "gpg>" { send "save\r" }
            timeout { puts "❌ Timeout moving subkeys to YubiKey"; exit 1 }
        }
        expect eof
EOF

    local LCL_EXIT_CODE=$?

    [ $LCL_EXIT_CODE -ne 0 ] &&  PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to move subkeys to YubiKey.${NC}"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $EXIT_CODE
}


setYubiKeyCardholderName () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_CONFIG_FILE=$1

    local LCL_FIRST_NAME=$(yq '.first_name' "$LCL_CONFIG_FILE")
    local LCL_LAST_NAME=$(yq '.last_name' "$LCL_CONFIG_FILE")

    if [[ -z "$LCL_FIRST_NAME" ]]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Cardholder first name is required.${NC}"
    fi

    if [[ -z "$LCL_LAST_NAME" ]]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Cardholder last name is required.${NC}"
    fi

    PrintTrace $TRACE_INFO "📝 Setting YubiKey cardholder name to: $LCL_FIRST_NAME $LCL_LAST_NAME"

    expect <<EOF
        log_user 1
        set timeout 60
        spawn gpg --card-edit
        expect "gpg/card>" { send "admin\r" }
        expect "gpg/card>" { send "name\r" }
        expect "Cardholder's surname:" { send "$LCL_LAST_NAME\r" }
        expect "Cardholder's given name:" { send "$LCL_FIRST_NAME\r" }
        expect {
            "gpg/card>" { send "quit\r" }
            timeout { puts "❌ Timeout while setting cardholder name"; exit 1 }
        }
        expect eof
EOF
    local LCL_EXIT_CODE=$?

    [ $LCL_EXIT_CODE -ne 0 ] && PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to set cardholder name on YubiKey.${NC}"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setYubiKeyLanguage () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_CONFIG_FILE=$1

    local LCL_LANG_CODE=$(yq '.lang_code' "$LCL_CONFIG_FILE")

    if [[ -z "$LCL_LANG_CODE" || ${#LCL_LANG_CODE} -ne 2 ]]; then
        PrintUsageAndExitWithCode 1 "${RED}❌ Please provide a valid 2-letter language code (e.g., 'en', 'fr', 'de').${NC}"
    fi

    PrintTrace $TRACE_INFO "🌐 Setting language on YubiKey to: $LCL_LANG_CODE"

    expect <<EOF
        log_user 1
        set timeout 60
        spawn gpg --card-edit
        expect "gpg/card>" { send "admin\r" }
        expect "gpg/card>" { send "lang\r" }
        expect "Language preferences:" { send "$LCL_LANG_CODE\r" }
        expect {
            "gpg/card>" { send "quit\r" }
            timeout { puts "❌ Timeout while setting language"; exit 1 }
        }
        expect eof
EOF
    local LCL_EXIT_CODE=$?

    [ $LCL_EXIT_CODE -ne 0 ] && PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to set language on YubiKey.${NC}"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


setYubiKeyLoginData () {
    local LCL_CONFIG_FILE="$1"

    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"

    local LCL_LOGIN_DATA=$(yq '.login_data' "$LCL_CONFIG_FILE")

    if [[ -z "$LCL_LOGIN_DATA" ]]; then
        PrintTrace $TRACE_INFO "${YLW}No Login data found in: $LCL_CONFIG_FILE.${NC}"
        return 1
    fi

    PrintTrace $TRACE_INFO "📝  Updating YubiKey Login data to: $LCL_LOGIN_DATA"

    expect <<EOF
        log_user 1
        set timeout 60
        spawn gpg --card-edit
        expect "gpg/card>" { send "admin\r" }
        expect "gpg/card>" { send "login\r" }
        expect "Login data (account name):" { send "$LCL_LOGIN_DATA\r" }
        expect {
            "gpg/card>" { send "quit\r" }
            timeout { puts "❌ Timeout while setting Login data"; exit 1 }
        }
        expect eof
EOF
    local LCL_EXIT_CODE=$?

    if [ $LCL_EXIT_CODE -ne 0 ]; then
        PrintTrace $TRACE_ERROR "${RED}❌ Failed to update YubiKey Login data.${NC}"
    else
        PrintTrace $TRACE_INFO "✅ YubiKey Login data updated successfully."
    fi

    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}


createSshPublicKey () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    local LCL_FINGER_PRINT="$1"
    local LCL_BACKUP_DIR="$2"
    local LCL_PUBLIC_SSH_KEY_FILE="$3"

    PrintTrace $TRACE_INFO "🔑 Generating SSH public key for $LCL_FINGER_PRINT"
    gpg --export-ssh-key "$LCL_FINGER_PRINT" > "$LCL_BACKUP_DIR/$LCL_PUBLIC_SSH_KEY_FILE"
    local LCL_EXIT_CODE=$?

    [ $LCL_EXIT_CODE -ne 0 ] && PrintUsageAndExitWithCode $LCL_EXIT_CODE "${RED}❌ Failed to generate SSH public key.${NC}"
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
    return $LCL_EXIT_CODE
}


deleteLocalGpgSecretKeys () {
    local LCL_FINGER_PRINT="$1"
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]} ($@)"
    PrintTrace $TRACE_INFO "🗑️  Deleting ALL local secret key material for $LCL_FINGER_PRINT"


    PrintTrace $TRACE_INFO "🔑 Listing secret keys... before"
    gpg --list-secret-keys

    # Collect keygrips for master and subkeys
    # local KEYGRIPS
    # KEYGRIPS=$(gpg --with-keygrip --list-secret-keys "$LCL_FINGER_PRINT" 2>/dev/null | awk '/Keygrip/ { print $3 }')

    # # Delete each keygrip's private file
    # for KEYGRIP in $KEYGRIPS; do
    #     local FILE="$HOME/.gnupg/private-keys-v1.d/${KEYGRIP}.key"
    #     if [[ -f "$FILE" ]]; then
    #         PrintTrace $TRACE_INFO "🔑 Deleting private key file: $FILE"
    #         rm -f "$FILE"
    #     else
    #         PrintTrace $TRACE_INFO "⚠️  Key file $FILE not found or already deleted"
    #     fi
    # done

    # Delete the reference from GnuPG's keyring (optional cleanup)
    gpg --batch --yes --delete-secret-keys "$LCL_FINGER_PRINT" || PrintTrace $TRACE_ERROR "⚠️ Could not delete key reference from secret keyring (probably already deleted)"
    # gpg --batch --yes --delete-keys "$LCL_FINGER_PRINT" || PrintTrace $TRACE_ERROR "⚠️ Could not delete key reference from public keyring (probably already deleted)"

    PrintTrace $TRACE_INFO "🔑 Listing secret keys... after"
    gpg --list-secret-keys

    PrintTrace $TRACE_INFO "✅ All secret keys for $LCL_FINGER_PRINT removed from local machine."
    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
}


test () {
    PrintTrace $TRACE_FUNCTION "-> ${FUNCNAME[0]}"


    PrintTrace $TRACE_FUNCTION "<- ${FUNCNAME[0]}"
}



#===========================
# main
#===========================
if [ -f $ABK_LIB_FILE ]; then
    source $ABK_LIB_FILE
else
    echo "ERROR: cannot find $ABK_LIB_FILE"
    echo "  $ABK_LIB_FILE contains common definitions and functions"
    exit 1
fi

echo
PrintTrace $TRACE_FUNCTION "-> $0 ($@)"

PrintTrace $TRACE_DEBUG "SCRIPT_NAME = $SCRIPT_NAME"
PrintTrace $TRACE_DEBUG "SCRIPT_PATH = $SCRIPT_PATH"
PrintTrace $TRACE_DEBUG "ABK_LIB_FILE = $ABK_LIB_FILE"

[ "$#" -ne $EXPECTED_NUMBER_OF_PARAMETERS ] && PrintUsageAndExitWithCode 1 "ERROR: invalid number of parameters, expected: $EXPECTED_NUMBER_OF_PARAMETERS"
set -euo pipefail

checkPrerequisiteToolsAreInstalled
checkYubiKeyPresence
parseConfigFile CONFIG_FILE "$1"
createMasterGpgKey FINGERPRINT "$CONFIG_FILE"
createGpgSubKeys "$CONFIG_FILE" "$FINGERPRINT"
setupBackupDir BACKUP_DIR "$CONFIG_FILE"

BASE_NAME=$(basename "$CONFIG_FILE" .yaml)
REVOCATION_KEY="$BASE_NAME.revocation.asc"
SECRET_MASTER_KEY="$BASE_NAME.master.sec.asc"
PUBLIC_MASTER_KEY="$BASE_NAME.master.pub.asc"
PUBLIC_SSH_KEY="$BASE_NAME.ssh.pub"

createGpgRevocationKey "$BACKUP_DIR" "$FINGERPRINT" "$REVOCATION_KEY"
backupMasterSecretGpgKey "$BACKUP_DIR" "$FINGERPRINT" "$SECRET_MASTER_KEY"
backupMasterPublicGpgKey "$BACKUP_DIR" "$FINGERPRINT" "$PUBLIC_MASTER_KEY"
backupGpgSubkeys "$BACKUP_DIR" "$FINGERPRINT" "$BASE_NAME"

resetYubiKeyPgpApplet
setYubiKeyResetCode
storeGpgSubKeysOnYubiKey "$FINGERPRINT"
setYubiKeyCardholderName "$CONFIG_FILE"
setYubiKeyLanguage "$CONFIG_FILE"
setYubiKeyLoginData "$CONFIG_FILE"

createSshPublicKey "$FINGERPRINT" "$BACKUP_DIR" "$PUBLIC_SSH_KEY"
deleteLocalGpgSecretKeys "$FINGERPRINT"

PrintTrace $TRACE_FUNCTION "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
