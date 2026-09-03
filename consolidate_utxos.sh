#!/bin/bash
set -Eeuo pipefail

# Consolidate UTXOs in the custom_signet wallet
CLI="bitcoin-cli -datadir=${BITCOIN_DIR} -rpcwallet=custom_signet"

echo "Starting UTXO consolidation..."

if [[ -f "${BITCOIN_DIR}/MINE_ADDRESS.txt" ]]; then
        ADDR=$(cat ~/.bitcoin/MINE_ADDRESS.txt)
    else
        ADDR=${MINETO:-$(bitcoin-cli -rpcwallet=custom_signet getnewaddress)}
fi

# Get wallet balance (excluding unconfirmed)
BALANCE=$($CLI getbalance)

echo "Consolidating $BALANCE BTC to $ADDR"

# Send all confirmed funds to the consolidation address
# This will automatically consolidate all UTXOs
# Using subtractfeefromamount to ensure we don't overdraw
TXID=$($CLI sendtoaddress "$ADDR" "$BALANCE" "" "" true)

echo "Consolidation transaction sent: $TXID"
