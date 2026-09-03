CLI="bitcoin-cli -datadir=${BITCOIN_DIR}" 

bitcoind --daemonwait
sleep 5
$CLI migratewallet custom_signet
if [[ $? -ne 0 ]]; then
    echo "Migration failed, exiting."
    exit 1
fi 
echo "Migrating privkey to descriptor format."
import_wif_to_descriptor.sh
echo "Private key imported into wallet as descriptor."
touch "${BITCOIN_DIR}/uses_modern_wallet"
echo "Migration completed successfully."
$CLI stop
sleep 5
