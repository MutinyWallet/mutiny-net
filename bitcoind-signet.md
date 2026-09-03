# Bitcoin Signet Docker Image
## ENV Variables

* `BLOCKPRODUCTIONDELAY` - default sleep period between mining blocks (**mining mode only**)
  * if ~/.bitcoin/BLOCKPRODUCTIONDELAY.txt is present will use this value, allowing the delay to be dynamically changed.
* `MINERENABLED` - flag for enabling mining chain
* `NBITS` - sets min difficulty in mining (**mining mode only**)
* `PRIVKEY` - private key of signet signer (**mining mode only**)
  * if `MINERENABLED=1` and not provided will generate this
* `MINETO` - mine to a static address, if not provided will make new address for each block (**mining mode only**)
* `SIGNETCHALLENGE` - sets the valid block producer for this signet
  * if `MINERENABLED=1` and not provided will generate this, if provded PRIVKEY also must be populated
  * Requied for client-mode
  * 
* `RPCUSER` - bitcoind RPC User
* `RPCPASSWORD` - bitcoind RPC password
* 
* `ONIONPROXY` - tor SOCK5 endpoint
* `TORPASSWORD` - tor control port password
* `TORCONTROL` - tor control port endpoint
* `I2PSAM` - I2P control endpoint
* `UACOMMENT` - UA Comment which would show on bitcoin-cli -netinfo printout
* 
* `ZMQPUBRAWBLOCK` - bitcoind setting
* `ZMQPUBRAWTX` - bitcoind setting
* `ZMQPUBHASHBLOCK` - bitcoind setting
* 
* `RPCBIND` - bitcoind setting
* `RPCALLOWIP` - bitcoind setting
* `WHITELIST` - bitcoind setting
* `ADDNODE` - add seeding node location, comma-separate for multiple nodes  (needed for client-mode)
* `EXTERNAL_IP` - add public IP/onion endpoint information, comma-seperated for multiple IPs.

