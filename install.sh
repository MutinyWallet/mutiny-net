touch ${BITCOIN_DIR}/uses_modern_wallet
echo "Generate or import keyset"
gen-signet-keys.sh
echo "Generate bitcoind configuration"
gen-bitcoind-conf.sh >${BITCOIN_DIR}/bitcoin.conf
echo "Setup Signet"
setup-signet.sh

if [[ "$MINE_GENESIS" == "1" ]]; then
    echo "Mine Genesis Block"
    mine-genesis.sh
fi

touch ${BITCOIN_DIR}/install_done