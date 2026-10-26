#!/bin/bash
# Make sure $MINER_WALLET is loaded and holds the block signing key. A new
# wallet lets the miner leave an oversized one unloaded.
set -euo pipefail

WALLET=${MINER_WALLET:-custom_signet}
CLI="bitcoin-cli -datadir=${BITCOIN_DIR}"

if $CLI listwallets | jq -e --arg w "$WALLET" 'any(.[]; . == $w)' >/dev/null; then
    exit 0
fi

if $CLI listwalletdir | jq -e --arg w "$WALLET" 'any(.wallets[]; .name == $w)' >/dev/null; then
    echo "Loading miner wallet $WALLET"
    $CLI loadwallet "$WALLET" true >/dev/null
    exit 0
fi

echo "Creating miner wallet $WALLET"
$CLI -named createwallet wallet_name="$WALLET" load_on_startup=true descriptors=true >/dev/null
WALLET="$WALLET" import-signing-key.sh
