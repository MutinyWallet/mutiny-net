# Mutinynet

This repo contains most of the deployment for [Mutinynet](https://mutinynet.com). It originally is a fork
of [Plebnet](https://github.com/nbd-wtf/bitcoin_signet) but has grown to include a lot more.

The main deployment is done with docker-compose. It contains various services:

* [bitcoind](https://github.com/bitcoin/bitcoin)
* [lnd](https://github.com/lightningnetwork/lnd)
* [rgs server](https://github.com/lightningdevkit/rapid-gossip-sync-server)
* faucet ([frontend](https://github.com/MutinyWallet/mutinynet-faucet)
  and [backend](https://github.com/MutinyWallet/mutinynet-faucet-rs))
* [mempool.space instance](https://github.com/mempool/mempool/)
* [electrs](https://github.com/romanz/electrs)
* [cashu mint](https://github.com/cashubtc/nutshell)

Most of these just pull the released docker images from dockerhub, but there are also some custom services:

* `bitcoind` this is a [custom build of bitcoind](https://github.com/benthecarman/bitcoin/releases) with soft forks and
  30s block time. It also contains the scripts to mine signet blocks.
* `electrs` this is a small fork of electrs to add a dockerfile and some fixes for signet, however these fixes ended up
  not being needed IIRC.
* `rapid-gossip-sync-server` this is a fork of rapid-gossip-sync-server to allow for a 10m snapshot interval. At the
  time there was no way to change the interval in the project, now there is but is has worked so far so I have not
  updated it.

Versions prior to 29.0 were using BDB wallet, system will automatically update your wallet to new descriptor format.
`PRIVKEY` prior to 29.0 was a WIF, now is descriptor on new wallets. 

## Running

To run the deployment, you need to have docker and docker-compose installed. Then you can run:

```bash
docker-compose up -d
```

This will start all the services. You can check the logs with:

```bash
docker-compose logs -f
```

You can also run the services individually:

```bash
docker-compose up -d bitcoind lnd rgs_server
```

You can create some aliases to make it easier to interact with bitcoind and lnd:

```bash
alias lncli="docker exec -it lnd /bin/lncli -n signet"
alias bitcoin-cli="docker exec -it bitcoind /usr/local/bin/bitcoin-cli"
```

## Updating

To update the deployment, you can run:

```bash
git pull
docker-compose pull
```

And then restart the services:

```bash
docker-compose up -d
```
