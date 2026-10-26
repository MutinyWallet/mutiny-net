#!/bin/bash
set -Eeuo pipefail

# Consolidate UTXOs in the miner wallet
CLI="bitcoin-cli -datadir=${BITCOIN_DIR} -rpcwallet=${MINER_WALLET:-custom_signet}"

echo "Starting UTXO consolidation..."

if [[ -f "${BITCOIN_DIR}/MINE_ADDRESS.txt" ]]; then
        ADDR=$(cat ~/.bitcoin/MINE_ADDRESS.txt)
    else
        ADDR=${MINETO:-$($CLI getnewaddress)}
fi

# Sending to an address outside this wallet would move the whole balance away.
if [[ $($CLI getaddressinfo "$ADDR" | jq -r .ismine) != "true" ]]; then
    echo "Skipping consolidation: $ADDR is not in the miner wallet"
    exit 0
fi

# Get wallet balance (excluding unconfirmed)
BALANCE=$($CLI getbalance)

echo "Consolidating $BALANCE BTC to $ADDR"

# Send all confirmed funds to the consolidation address
# This will automatically consolidate all UTXOs
# Using subtractfeefromamount to ensure we don't overdraw
TXID=$($CLI sendtoaddress "$ADDR" "$BALANCE" "" "" true)

echo "Consolidation transaction sent: $TXID"
