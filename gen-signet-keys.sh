DATADIR=${DATADIR:-"regtest-temp"}
BITCOINCLI=${BITCOINCLI:-"bitcoin-cli -regtest -datadir=$DATADIR "}
BITCOIND=${BITCOIND:-"bitcoind -datadir=$DATADIR -regtest -daemon "}

write_files() {
    echo "PRIVKEY="
    cat $BITCOIN_DIR/PRIVKEY.txt
    echo "SIGNETCHALLENGE=" $SIGNETCHALLENGE
    echo $ADDR > $BITCOIN_DIR/ADDR.txt
    echo $PUBKEY > $BITCOIN_DIR/PUBKEY.txt
    echo $SIGNETCHALLENGE >$BITCOIN_DIR/SIGNETCHALLENGE.txt
}

if [[ "$MINERENABLED" == "1" ]]; then
    if [[ ("$SIGNETCHALLENGE" == "" || "$PRIVKEY" == "") ]]; then
        echo "Generating new signetchallange and privkey."
        #clean if exists
        rm -rf $DATADIR
        #make it fresh
        mkdir $DATADIR
        #kill any daemon running stuff
        pkill bitcoind
        #minimal config file (hardcode bitcoin:bitcoin for rpc)
        echo "
        regtest=1
        server=1
        rpcauth=bitcoin:c8c8b9740a470454255b7a38d4f38a52\$e8530d1c739a3bb0ec6e9513290def11651afbfd2b979f38c16ec2cf76cf348a
        rpcuser=bitcoin
        rpcpassword=bitcoin
        " >$DATADIR/bitcoin.conf
        #start daemon
        $BITCOIND -wallet="temp"
        #wait a bit for startup
        sleep 5s

        #create wallet
        $BITCOINCLI -named createwallet wallet_name="temp" descriptors=true
        #Get the signet script from the 86 descriptor
        ADDR=$($BITCOINCLI getnewaddress)
        SIGNETCHALLENGE=$($BITCOINCLI getaddressinfo $ADDR | jq -r ".scriptPubKey")
        PUBKEY=$($BITCOINCLI getaddressinfo $ADDR | jq .pubkey | tr -d '""')
        # Dumping descriptor wallet privatekey
        $BITCOINCLI listdescriptors true | jq -r ".descriptors | .[].desc" >> $BITCOIN_DIR/PRIVKEY.txt

        #don't need regtest anymore
        $BITCOINCLI stop
        #cleanup
        rm -rf $DATADIR
    else
        echo "$PRIVKEY" > $BITCOIN_DIR/PRIVKEY.txt
        echo "$SIGNETCHALLENGE" > $BITCOIN_DIR/SIGNETCHALLENGE.txt
        echo "Imported signetchallange and privkey being used."
    fi
fi

write_files