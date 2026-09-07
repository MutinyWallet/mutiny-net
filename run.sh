#!/bin/bash
# bitcoind runs as a child of this script. docker-entrypoint.sh execs this
# script, so it is PID 1. When bitcoind exits, this script exits, the container
# stops, and Docker's restart policy starts it again. The old daemon mode left
# the container "running" with no bitcoind after a crash.

shutdown() {
  echo "Container is shutting down, lets make sure bitcoind flushes the db."
  bitcoin-cli stop || true
}
trap shutdown SIGTERM SIGHUP SIGQUIT SIGINT

bitcoind &
BITCOIND_PID=$!

# Wait for RPC.
until bitcoin-cli getblockchaininfo >/dev/null 2>&1; do
  if ! kill -0 "$BITCOIND_PID" 2>/dev/null; then
    echo "bitcoind exited during startup" >&2
    wait "$BITCOIND_PID"
    exit 1
  fi
  sleep 1
done

echo "get magic"
magic=$(grep -m1 magic /root/.bitcoin/signet/debug.log)
magic=${magic:(-8)}
echo $magic > /root/.bitcoin/MAGIC.txt

# if in mining mode
if [[ "$MINERENABLED" == "1" ]]; then
    mine.sh &
fi

# A signal interrupts wait, so loop until bitcoind is really gone.
status=0
while kill -0 "$BITCOIND_PID" 2>/dev/null; do
  wait "$BITCOIND_PID"
  status=$?
done
echo "bitcoind exited with status $status"
exit "$status"
