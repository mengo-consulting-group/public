#!/bin/bash

# Verify if the operating system is Ubuntu 20.04, 22.04 or 24.04
verify_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$NAME" == "Ubuntu" && ( "$VERSION_ID" == "20.04" || "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ) ]]; then
            echo "Operating system is Ubuntu $VERSION_ID"
        else
            echo "This script only supports Ubuntu 20.04, 22.04 or 24.04"
            exit 1
        fi
    else
        echo "Cannot determine the operating system version"
        exit 1
    fi
}

# Ensure the user has sudo access without password
grant_sudo_without_password() {
    SUDOERS_FILE="/etc/sudoers.d/$(whoami)"
    if sudo grep -q "$(whoami) ALL=(ALL) NOPASSWD:ALL" "$SUDOERS_FILE" 2>/dev/null; then
        echo "Sudo access without password is already granted to the user"
    else
        echo "$(whoami) ALL=(ALL) NOPASSWD:ALL" | sudo tee "$SUDOERS_FILE" >/dev/null
        echo "Sudo access without password has been granted to the user"
    fi
}

# Ensure the user has mengo-bot public key from github added to local authorized_keys file
add_mengo_bot_public_key() {
    MENGO_BOT_KEY_URL="https://github.com/mengo-bot.keys"
    AUTHORIZED_KEYS_FILE="$HOME/.ssh/authorized_keys"

    if ! grep -q "$(curl -s $MENGO_BOT_KEY_URL)" "$AUTHORIZED_KEYS_FILE"; then
        echo "Adding mengo-bot public key to $AUTHORIZED_KEYS_FILE"
        curl -s $MENGO_BOT_KEY_URL >> "$AUTHORIZED_KEYS_FILE"
    else
        echo "mengo-bot public key is already present in $AUTHORIZED_KEYS_FILE"
    fi
}

verify_ubuntu_version
add_mengo_bot_public_key
grant_sudo_without_password
