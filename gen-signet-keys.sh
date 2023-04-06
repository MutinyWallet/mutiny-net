DATADIR=${DATADIR:-"regtest-temp"}
BITCOINCLI=${BITCOINCLI:-"bitcoin-cli -regtest -datadir=$DATADIR "}
BITCOIND=${BITCOIND:-"bitcoind -datadir=$DATADIR -regtest -daemon "}

write_files() {
    # echo "ADDR=" $ADDR
    echo "PRIVKEY=" $PRIVKEY
    # echo "PUBKEY=" $PUBKEY
    echo "SIGNETCHALLENGE=" $SIGNETCHALLENGE
    # echo $ADDR > ~/.bitcoin/ADDR.txt
    echo $PRIVKEY >~/.bitcoin/PRIVKEY.txt
    # echo $PUBKEY > ~/.bitcoin/PUBKEY.txt
    echo $SIGNETCHALLENGE >~/.bitcoin/SIGNETCHALLENGE.txt
}

if [[ "$MINERENABLED" == "1" && ("$SIGNETCHALLENGE" == "" || "$PRIVKEY" == "") ]]; then
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
    $BITCOINCLI -named createwallet wallet_name="tmp" descriptors=false
    #export future signet seeding key data
    ADDR=$($BITCOINCLI getnewaddress)
    PRIVKEY=$($BITCOINCLI dumpprivkey $ADDR)
    PUBKEY=$($BITCOINCLI getaddressinfo $ADDR | jq .pubkey | tr -d '""')
    #don't need regtest anymore
    $BITCOINCLI stop
    SIGNETCHALLENGE=$(echo '5121'$PUBKEY'51ae')

    #cleanup
    rm -rf $DATADIR
else
    echo "Imported signetchallange and privkey being used."
fi

write_files
