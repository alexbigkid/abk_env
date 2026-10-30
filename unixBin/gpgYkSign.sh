#!/usr/bin/env bash
# git gpg.program wrapper: signs with the key of whichever YubiKey is currently plugged in.
# git calls it like gpg, e.g.: gpgYkSign.sh --status-fd=2 -bsau <user.signingkey>
# The key after -u/--local-user is replaced with the signing subkey of the connected card,
# so any number of YubiKeys (each with its own key) can be used without changing git config.
# Without a card, or for any other operation (e.g. --verify), arguments pass through unchanged.
# NOTE: stdout carries the signature for git, so nothing else may be printed to it.

#---------------------------
# variables definitions
#---------------------------
GPG_BIN=$(command -v gpg)
[ -z "$GPG_BIN" ] && [ -x /opt/homebrew/bin/gpg ] && GPG_BIN=/opt/homebrew/bin/gpg
[ -z "$GPG_BIN" ] && [ -x /usr/local/bin/gpg ] && GPG_BIN=/usr/local/bin/gpg
[ -z "$GPG_BIN" ] && { echo "gpgYkSign.sh: gpg not found" >&2; exit 1; }


#---------------------------
# functions
#---------------------------
getCardSigningKeyFp() {
    # fpr:<sig>:<enc>:<auth>: from the connected card, empty if no card
    "$GPG_BIN" --card-status --with-colons 2>/dev/null | awk -F: '$1=="fpr" && $2!="" {print $2; exit}'
}


#---------------------------
# main
#---------------------------
LCL_ARGS=()
LCL_REPLACE_NEXT=0
LCL_CARD_KEY_FP=""

for LCL_ARG in "$@"; do
    if [ $LCL_REPLACE_NEXT -eq 1 ]; then
        LCL_REPLACE_NEXT=0
        [ -n "$LCL_CARD_KEY_FP" ] && LCL_ARG="${LCL_CARD_KEY_FP}!"
    else
        case "$LCL_ARG" in
            -u|--local-user|-[!-]*u)
                # -u, --local-user or bundled short options ending in u (git uses -bsau)
                LCL_CARD_KEY_FP=$(getCardSigningKeyFp)
                LCL_REPLACE_NEXT=1
                ;;
            --local-user=*)
                LCL_CARD_KEY_FP=$(getCardSigningKeyFp)
                [ -n "$LCL_CARD_KEY_FP" ] && LCL_ARG="--local-user=${LCL_CARD_KEY_FP}!"
                ;;
        esac
    fi
    LCL_ARGS+=("$LCL_ARG")
done

exec "$GPG_BIN" "${LCL_ARGS[@]}"
