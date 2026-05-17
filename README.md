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

## Activating a soft fork

Bitcoin Inquisition "heretical" deployments lock in as soon as **one** block in
the current 432-block signet period is mined with `nVersion == signal_activate`.
The next period it becomes active.

`signal_activate = 0x60000000 | binana_id`, where
`binana_id = ((year % 32) << 22) | (number << 8) | revision` from the
deployment's `src/binana/*.json` entry. Use `calc_nversion.py` to compute it:

```bash
./calc_nversion.py 2026 1 0
# or from the binana JSON itself:
./calc_nversion.py path/to/bitcoin/src/binana/templatehash.json
```

For example, TEMPLATEHASH (BIP446, binana `[2026, 1, 0]`) gives `0x62800100`.

The `miner` script inside `bitcoind-miner` already accepts `--nversion`, so we
can mine one signalling block directly without modifying `mine.sh`. Signet
blocks at min-difficulty solve fast enough to beat the next loop iteration:

```bash
docker exec bitcoind-miner sh -c '
  miner --debug \
        --cli="bitcoin-cli -datadir=/root/.bitcoin -rpcwallet=custom_signet" \
        generate \
        --grind-cmd="bitcoin-util grind" \
        --addr=tb1qd28npep0s8frcm3y7dxqajkcy2m40eysplyr9v \
        --nbits=1e0377ae \
        --nversion=0x62800100 \
        --set-block-time=$(date +%s)
'
```

Check the state transition with:

```bash
bitcoin-cli getdeploymentinfo | jq '.deployments.templatehash'
```

You should see `current_state` go `started` → `locked_in` → `active` over the
next two 432-block periods.

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
