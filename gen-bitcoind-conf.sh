SIGNETCHALLENGE=${SIGNETCHALLENGE:-$(cat ~/.bitcoin/SIGNETCHALLENGE.txt)}

RPCAUTH=$(/usr/local/bin/rpcauth.py $RPCUSER $RPCPASSWORD | tr -d '\n')
echo "signet=1"

if [[ "$COOKIEFILE" == "true" ]]; then
echo "rpccookiefile=/root/.bitcoin/.cookie
rpcauth=$RPCAUTH"
else
echo "rpcauth=$RPCAUTH
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD"
fi

echo "txindex=1
blockfilterindex=1
peerblockfilters=1
coinstatsindex=1
dnsseed=0
persistmempool=1
uacomment=$UACOMMENT"

if [[ "$EXTERNAL_IP" != "" ]]; then
    echo $EXTERNAL_IP | tr ',' '\n' | while read ip; do
        echo "externalip=$ip"
    done
fi

echo "[signet]
rest=1
daemon=1
listen=1
server=1
acceptnonstdtxn=1
v2transport=1
discover=1
signetblocktime=$BLOCKPRODUCTIONDELAY
signetchallenge=$SIGNETCHALLENGE
zmqpubrawblock=$ZMQPUBRAWBLOCK
zmqpubrawtx=$ZMQPUBRAWTX
zmqpubhashblock=$ZMQPUBHASHBLOCK
rpcbind=$RPCBIND
rpcallowip=$RPCALLOWIP
whitelist=$WHITELIST
fallbackfee=0.0002"
minrelaytxfee=0.00000100
datacarriersize=100000

if [[ "$ADDNODE" != "" ]]; then
    echo $ADDNODE | tr ',' '\n' | while read node; do
        echo "addnode=$node"
    done
fi
 

if [[ "$I2PSAM" != "" ]]; then
    echo "i2psam=$I2PSAM"
fi
if [[ "$ONIONPROXY" != "" ]]; then
    echo "onion=$ONIONPROXY" # unless have static IP won't resolve the control port as domain
fi

if [[ "$TORPASSWORD" != "" ]]; then
    echo "torpassword=$TORPASSWORD"
fi

if [[ "$TORCONTROL" != "" ]]; then
    echo "torcontrol=$TORCONTROL"
fi
