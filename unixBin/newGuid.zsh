#!/bin/zsh

NEW_GUID=$(uuidgen | tr "[:upper:]" "[:lower:]")
if [ "$ABK_UNIX_TYPE" = "mac" ]; then
    echo "Copying to clipboard new GUID: $NEW_GUID"
    echo $NEW_GUID | tr -d '\n' | pbcopy
else
    if [ "$(command -v xclip)" == "" ]; then
        echo "New GUID: $NEW_GUID"
    else
        echo "Copying to clipboard new GUID: $NEW_GUID"
        echo $NEW_GUID | xclip
        echo $NEW_GUID | xclip -sel clip
    fi
fi

exit 0
