#!/bin/bash

# TODO: This script should calculate the target hosts based on the ansible inventory using the MENGO_AGENT_ID. Then loop over those hosts and copy the public key to them.

# Usage: ./setup_public_ssh_key.sh <user@hostname>

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <user@hostname>"
    exit 1
fi

TARGET=$1
PUBLIC_KEY_FILE="/opt/mengo/agent/.ssh_public_key"

if [ ! -f "$PUBLIC_KEY_FILE" ]; then
    echo "Public key file not found at $PUBLIC_KEY_FILE"
    exit 1
fi

ssh-copy-id -i "$PUBLIC_KEY_FILE" "$TARGET"
