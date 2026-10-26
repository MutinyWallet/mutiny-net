
bitcoind -datadir=$BITCOIN_DIR --daemonwait -persistmempool #-deprecatedrpc=create_bdb
bitcoin-cli -datadir=$BITCOIN_DIR -named createwallet wallet_name="custom_signet" load_on_startup=true descriptors=true


# Set privkey if pushed from ENV and doesn't exist in file systems yet.
if [ ! -f "$BITCOIN_DIR/PRIVKEY.txt" ]; then
    echo "$PRIV_KEY" > "$BITCOIN_DIR/PRIVKEY.txt"
fi

#only used in case of mining node and modern wallet
if [[ -f "${BITCOIN_DIR}/uses_modern_wallet" && "$MINERENABLED" == "1" ]]; then
    WALLET=custom_signet import-signing-key.sh
fi
