#!/bin/bash

# Find the avatar file for the user $1

USER_NAME=$1

POSSIBLE_PATHS=(
    "/var/lib/AccountsService/icons/$USER_NAME"
    "/home/$USER_NAME/.face"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    # Check if the file exists and is readable
    if [ -r "$path" ]; then
        echo "$path"
        exit 0
    fi
done

exit 1
