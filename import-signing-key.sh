#!/bin/bash
# Import the signet block signing key from PRIVKEY.txt into $WALLET.
set -euo pipefail

WALLET=${WALLET:-custom_signet}

if [ "$PRIVKEY_MODE" == "legacy" ]; then
    WALLET="$WALLET" import_wif_to_descriptor.sh
else
    line_count=0
    while read line; do
        # Increment the line counter
        line_count=$((line_count+1))

        # Check if the line count is even or odd
        if [ $((line_count % 2)) -eq 0 ]; then
            is_even="true"
        else
            is_even="false"
        fi

        DESCRIPTORS="
        {
            \"desc\": \"${line}\",
            \"timestamp\": 0,
            \"active\": true,
            \"internal\": ${is_even},
            \"range\": [
                0,
                999
            ]
        }"

        DESCRIPTORS="[${DESCRIPTORS//[$'\t\r\n ']}]"

        bitcoin-cli -datadir=$BITCOIN_DIR -rpcwallet="$WALLET" importdescriptors "$DESCRIPTORS" 2>&1 > /dev/null

    done < $BITCOIN_DIR/PRIVKEY.txt
fi
