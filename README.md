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
cp .env.sample .env
# Replace every placeholder before you continue.
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

## Spark (self-hosted operator + SSP)

The `spark`, `spark2`, `ldk-server`, and `ssp` services run a 2-of-2 Spark
operator set and the MutinyNet SSP. The SSP embeds its funded Breez Spark
wallet, so there is no JavaScript sidecar. The operator and LDK images build
from pinned commits. Compose pins the SSP image to a tested `sha-*` tag.

Boot order:

```bash
docker compose up -d bitcoind-services postgres
docker compose up -d --build --wait spark spark2
./spark-operator-pubkeys.sh                # copy both lines to .env
install -d -m 700 ~/volumes/ssp-data
# Existing deployments only: preserve the funded wallet identity.
if [ ! -s ~/volumes/ssp-data/spark.mnemonic ]; then
  test -s ~/volumes/sidecar-data/sidecar.mnemonic
  install -m 600 ~/volumes/sidecar-data/sidecar.mnemonic \
    ~/volumes/ssp-data/spark.mnemonic
fi
docker compose pull ssp
docker compose build ldk-server
docker compose up -d --no-build --wait ldk-server ssp
curl --fail http://127.0.0.1:5000/health   # ldk_mode must be "live"
node --env-file=.env fund-ssp.mjs
```

Wallets use `spark-wallet-config.mutinynet.example.json` (SIGNET, custom SOs,
`https://mutinynet.com/api` electrs, `https://ssp.mutinynet.com` SSP).
Set its SSP identity to the `ssp_identity_pubkey` from `/health`. The two
operator keys must match the output of `spark-operator-pubkeys.sh`. Expose the
SSP through `nginx/ssp.mutinynet.com` and reload nginx.

Notes:

* Set `SPARK_ADMIN_TOKEN` before you start the SSP. Back up `ssp-data`, which
  contains the SSP database and Spark mnemonic, plus the LDK data.
* Existing sidecar deployments must copy `sidecar.mnemonic` as shown above.
* The first operator restart after this update rotates legacy TLS certificates
  that were marked as certificate authorities. The entrypoint keeps one
  `.legacy-ca` backup beside each old certificate and key.
  Keep the old file offline until the new SSP passes live transfer tests.
* Compose sets `SPARK_MNEMONIC_REQUIRED=1`, so startup fails if the wallet key
  is absent. Change it only for the first boot of a new, unfunded SSP wallet.
* `SSP_FROST_OPERATORS` is required for Lightning receives. Do not start the
  SSP until you copy the complete helper output to `.env`.
* The SSP does not use fake Lightning in production. Its `/health` response
  must show `"ldk_mode":"live"`.
* Fund the LDK on-chain wallet and open channels with `ldk-server-cli`.
  Receives need inbound capacity. Sends need outbound capacity.
* Lightning receives use exact SSP wallet leaves. Keep common invoice amounts
  in the funding ladder. Monitor `/health` values under `spark`.
* `reset-spark.sh` asks for confirmation and deletes all operator, SSP, and
  embedded-wallet state. `--full` also deletes LDK wallet and channel state.
