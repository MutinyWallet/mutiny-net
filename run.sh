#!/bin/bash
set -uo pipefail

BITCOIND_PID=""
MINER_PID=""
SHUTTING_DOWN=0

shutdown_gracefully() {
    SHUTTING_DOWN=1
    echo "Container is shutting down; asking bitcoind to flush its database."
    if [ -n "$MINER_PID" ]; then
        kill "$MINER_PID" 2>/dev/null || true
    fi
    bitcoin-cli -signet -datadir="$BITCOIN_DIR" stop >/dev/null 2>&1 \
        || kill "$BITCOIND_PID" 2>/dev/null \
        || true
}
trap shutdown_gracefully SIGTERM SIGHUP SIGQUIT SIGINT

# Override daemon=1 from bitcoin.conf so this shell can supervise the process.
bitcoind -daemon=0 &
BITCOIND_PID=$!

ready=0
for _ in $(seq 1 900); do
    if ! kill -0 "$BITCOIND_PID" 2>/dev/null; then
        wait "$BITCOIND_PID"
        exit $?
    fi
    if bitcoin-cli -signet -datadir="$BITCOIN_DIR" getblockchaininfo >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
if [ "$ready" -ne 1 ]; then
    echo "bitcoind did not become ready within 15 minutes" >&2
    kill "$BITCOIND_PID" 2>/dev/null || true
    wait "$BITCOIND_PID" 2>/dev/null || true
    exit 1
fi

echo "get magic"
magic=$(grep -m1 magic "$BITCOIN_DIR/signet/debug.log")
magic=${magic:(-8)}
echo "$magic" > "$BITCOIN_DIR/MAGIC.txt"

if [[ "$MINERENABLED" == "1" ]]; then
    mine.sh &
    MINER_PID=$!
fi

status=0
wait "$BITCOIND_PID" || status=$?
if [ "$SHUTTING_DOWN" -eq 1 ]; then
    wait "$BITCOIND_PID" 2>/dev/null || true
    status=0
fi
if [ -n "$MINER_PID" ]; then
    kill "$MINER_PID" 2>/dev/null || true
    wait "$MINER_PID" 2>/dev/null || true
fi
exit "$status"
