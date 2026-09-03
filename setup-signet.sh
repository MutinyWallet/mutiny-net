
bitcoind -datadir=$BITCOIN_DIR --daemonwait -persistmempool #-deprecatedrpc=create_bdb
bitcoin-cli -datadir=$BITCOIN_DIR -named createwallet wallet_name="custom_signet" load_on_startup=true descriptors=true


# Set privkey if pushed from ENV and doesn't exist in file systems yet.
if [ ! -f "$BITCOIN_DIR/PRIVKEY.txt" ]; then
    echo "$PRIV_KEY" > "$BITCOIN_DIR/PRIVKEY.txt"
fi

#only used in case of mining node and modern wallet
if [[ -f "${BITCOIN_DIR}/uses_modern_wallet" && "$MINERENABLED" == "1" ]]; then

    if [ "$PRIVKEY_MODE" == "legacy" ]; then
        import_wif_to_descriptor.sh
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
            
            bitcoin-cli -datadir=$BITCOIN_DIR importdescriptors "$DESCRIPTORS" 2>&1 > /dev/null
            
        done < $BITCOIN_DIR/PRIVKEY.txt
    fi

    
fi