#!/bin/bash
set -eo pipefail

mkdir -p "${BITCOIN_DIR}" 
# check if this is first run if so run init if config
if [[ ! -f "${BITCOIN_DIR}/install_done" ]]; then
  echo "install_done file not found, running install.sh."
  install.sh #this is config based on args passed into mining node or peer.
  # install.sh leaves a daemonized bitcoind running. Stop it so run.sh can
  # start bitcoind in the foreground.
  bitcoin-cli stop || true
  while pgrep -x bitcoind >/dev/null; do sleep 1; done
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

# Replace this shell so the command is PID 1 and receives container signals.
exec "$@"
