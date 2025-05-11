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
  if [[ ! -f "${BITCOIN_DIR}/uses_modern_wallet" ]]; then
    echo "Hmm looks like you are using a legacy wallet, lets get that migrated over."
    migrate.sh
    sleep 4
    echo "Migration complete, lets start bitcoind."
  fi
  echo "rewrite bitcoin.conf"
  gen-bitcoind-conf.sh >~/.bitcoin/bitcoin.conf
fi
    
$@ &
echo "Infinate loop"
while true
do
  tail -f /dev/null & wait ${!}
done