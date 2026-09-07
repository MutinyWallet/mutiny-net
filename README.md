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
from pinned commits. The SSP image is published separately; production
deployments should replace its moving tag with a tested immutable `sha-*` tag.

The operators also listen on `11010` and `11011` for the authenticated
`SparkSspInternalService`. These ports are visible only on the Compose network:
they have no host port mapping and are not routed by nginx. The SSP continues
to use the public operator listeners for normal wallet operations and uses the
dedicated listeners only for on-demand leaf splitting.

On-demand splitting spans three repositories. Before deploying it, publish the
Spark operator changes and the open-ssp changes, then update this repository's
`spark/Dockerfile` `SPARK_REF` and `ssp` image to those immutable revisions.
Local, uncommitted sibling-repository changes are not included in either Docker
build. Do not enable the new listener against the currently pinned operator
revision, because that binary does not recognize `--ssp-grpc-port`.

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
  in the funding ladder until on-demand splitting is deployed. Once enabled,
  the SSP can repeatedly split an owned leaf to make the requested amount and
  retain the remainder. `SSP_MIN_SPLIT_CHILD_SATS` controls the minimum value
  of either child and defaults to the 330-sat P2TR relay-dust threshold.
  Lower values deliberately create off-chain-only leaves that cannot be
  independently relayed under default Bitcoin Core policy. Monitor `/health`
  values under `spark`.
* `reset-spark.sh` asks for confirmation and deletes all operator, SSP, and
  embedded-wallet state. `--full` also deletes LDK wallet and channel state.

## Hardening

These controls protect the public services. Deploy them in this order.

### nginx

* `nginx/nginx.conf` and every vhost in `nginx/` are the live config:
  `nginx/deploy.sh` links them into `/etc/nginx`, runs `nginx -t`, and
  reloads. Run `nginx/deploy.sh --check` to see drift between the host and
  the repo without changing anything. After the first run, a `git pull`
  changes the files nginx reads, and the next `deploy.sh` (or any reload)
  applies them.
* Vhosts define their own `limit_req_zone` and `limit_conn_zone` entries and
  include `spark-grpc-proxy.conf` and `electrs-cors.conf` from
  `/root/mutiny-net/nginx/`.
* The Electrum port sits behind the `stream {}` block in `nginx/nginx.conf`,
  which includes `electrum-stream.conf`. The compose file binds electrs to `127.0.0.1:50003`, and nginx listens on
  `50001`. Reload nginx after `docker compose up -d mempool_electrs`, because
  both cannot own port 50001. Clients use `electrum.mutinynet.com:50001`,
  which must stay a DNS-only record; Cloudflare-proxied names cannot carry
  raw TCP. The websocat bridge on the host keeps connecting to
  `127.0.0.1:50001`; loopback is exempt from the per-IP cap.
* Both operator vhosts return 404 for the SO-to-SO and mock services. Requests
  to the challenge RPCs get a tighter per-IP limit than the rest.

### Spark authorization

`spark-config.yaml` sets `service_authz.mode: 3` (enforce). The operator then
accepts internal methods only from peers whose source address starts with
`10.`, so the compose file pins the default network to `10.213.87.0/24` and
gives the operators and the SSP fixed addresses. Changing the network subnet
recreates every container:

```bash
docker compose down            # bitcoind index reload takes minutes afterwards
docker compose up -d --build
```

If SO-to-SO calls fail after the change, set `mode: 2` (warn) to log instead of
deny, and check the operator logs for `authz`.

Rate limits and concurrency caps live under `knobs.static_values` in
`spark-config.yaml`. The `rate_limiter` block only switches the limiter on.

The operators and the SSP have fixed addresses above `.128`, and the network's
`ip_range` keeps dynamic allocation below it. Docker does not reserve a
service's fixed address from other services, so without the range a container
that starts first can take it and the operator fails with "Address already in
use".

### Containers

* `docker compose up -d` recreates only services whose own config changed,
  plus everything when something shared changes: the network, the logging
  driver, or a `depends_on` chain. Run `docker compose up -d --dry-run` first
  and read which containers it would recreate. Both bitcoind nodes should
  appear only when you mean it; each restart costs a block index reload.
* Container logs go to the host journal (`journalctl CONTAINER_NAME=spark -f`
  or `docker logs`). They survive container recreation. Retention is bounded
  by `host/journald-mutinynet.conf`, installed to
  `/etc/systemd/journald.conf.d/`. Switching the driver recreates every
  container, so do it in a planned window.
* The miner's health check fails when the chain tip is older than ten
  minutes, so a stalled miner shows as unhealthy. The services node only
  checks RPC.
* Every service has `pids_limit`, and most have `mem_limit`. The values are a
  first cut. Watch `docker stats` and raise a limit before it causes restarts.
  Bitcoin and the databases have reservations only.
* Both bitcoind containers run bitcoind as PID 1 and restart when it exits.
  Both have health checks.
* bitcoind whitelists only the Compose subnet. Public peers get default
  treatment.
* Our own images use moving tags on purpose so `docker compose pull` picks up
  a new build without a commit here. The operator image is built by the
  "Build Spark operator image" workflow from `SPARK_REF`; after pushing a
  bump, wait for it, then pull and restart both operators. Set
  `SPARK_OPERATOR_TAG` to a pinned-ref tag to freeze it.
* LNDK logs at `info` and sends its file log to `/dev/null`. Docker rotates
  stdout.

### Audit

`./audit-spark.sh [days]` searches the nginx access logs and operator logs for
calls to the services that were reachable before this hardening, and runs
sanity queries against both operator databases. A clean access log for the
whole exposure window is the strongest evidence that nothing happened.
