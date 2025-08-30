#!/bin/bash
set -Eeuo pipefail
# Define mining constants
CLI="bitcoin-cli -datadir=${BITCOIN_DIR} -rpcwallet=custom_signet"
GRIND="bitcoin-util grind"

NBITS=${NBITS:-"1e0377ae"} #minimum difficulty in signet

echo "Waiting until Chain tip age is < $CHAIN_TIP_AGE seconds before mining start..."
wait_chain_sync.sh $CHAIN_TIP_AGE

while true; do
    if [[ -f "${BITCOIN_DIR}/MINE_ADDRESS.txt" ]]; then
        ADDR=$(cat ~/.bitcoin/MINE_ADDRESS.txt)
    else
        ADDR=${MINETO:-$(bitcoin-cli -rpcwallet=custom_signet getnewaddress)}
    fi
    if [[ -f "${BITCOIN_DIR}/BLOCKPRODUCTIONDELAY.txt" ]]; then
        BLOCKPRODUCTIONDELAY_OVERRIDE=$(cat ~/.bitcoin/BLOCKPRODUCTIONDELAY.txt)
        echo "Delay OVERRIDE before next block" $BLOCKPRODUCTIONDELAY_OVERRIDE "seconds."
        sleep $BLOCKPRODUCTIONDELAY_OVERRIDE
    else
        BLOCKPRODUCTIONDELAY=${BLOCKPRODUCTIONDELAY:="0"}
        if [[ BLOCKPRODUCTIONDELAY -gt 0 ]]; then
            echo "Delay before next block" $BLOCKPRODUCTIONDELAY "seconds."
            sleep $BLOCKPRODUCTIONDELAY
        fi
    fi
    #echo "Mine To:" $ADDR --addr=$ADDR 
    miner --debug --cli="$CLI" generate --grind-cmd="$GRIND" --addr=$ADDR --nbits=$NBITS  --set-block-time=$(date +%s) || true

done
