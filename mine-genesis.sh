#!/bin/bash
ADDR=${ADDR:-$(bitcoin-cli getnewaddress "gen0" bech32)}
NBITS=${NBITS:-"1e0377ae"} #minimum difficulty in signet
miner --cli="bitcoin-cli" generate --address=$ADDR --grind-cmd="bitcoin-util grind" --nbits=$NBITS --set-block-time=$(date +%s)


