#!/bin/bash
set -eo pipefail

shutdown_gracefully(){

  echo "Container is shutting down, lets make sure bitcoind flushes the db."
  bitcoin-cli stop
  sleep 5
}
trap shutdown_gracefully SIGTERM SIGHUP SIGQUIT SIGINT

mkdir -p "${BITCOIN_DIR}" 
# check if this is first run if so run init if config
if [[ ! -f "${BITCOIN_DIR}/install_done" ]]; then
  echo "install_done file not found, running install.sh."
  install.sh #this is config based on args passed into mining node or peer.
else
  echo "install_done file exists, skipping setup process."
  echo "rewrite bitcoin.conf"
  gen-bitcoind-conf.sh >~/.bitcoin/bitcoin.conf
fi
    
$@ &
echo "Infinite loop"
while true
do
  tail -f /dev/null & wait ${!}
done