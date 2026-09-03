// Fund the sidecar liquidity wallet: single-use address <- bitcoind, mine, claim.
// Env: SPARK_SDK_DIST, SO_HOSTS, SSP_URL/SSP_IDENTITY_PUBKEY, SPARK_NETWORK,
// SIDECAR_MNEMONIC or SIDECAR_MNEMONIC_FILE, BITCOIN_RPC_* (see ../e2e/faucet.mjs),
// FUND_AMOUNT_SATS (default 10000000 = 0.1 BTC).
import fs from "node:fs";

const SDK_DIST = process.env.SPARK_SDK_DIST;
if (!SDK_DIST) throw new Error("set SPARK_SDK_DIST");
const { SparkWallet } = await import(SDK_DIST);
const { sendToAddress, mineAndWait } = await import("./faucet.mjs");

const NETWORK = process.env.SPARK_NETWORK ?? "LOCAL";
const SO_HOSTS = (process.env.SO_HOSTS ?? "127.0.0.1:8535,127.0.0.1:8536,127.0.0.1:8537").split(",");
const LOCAL_PUBKEYS = (process.env.SO_IDENTITY_PUBKEYS ??
  [
    "0322ca18fc489ae25418a0e768273c2c61cabb823edfb14feb891e9bec62016510",
    "0341727a6c41b168f07eb50865ab8c397a53c7eef628ac1020956b705e43b6cb27",
    "0305ab8d485cc752394de4981f8a5ae004f2becfea6f432c9a59d5022d8764f0a6",
    "0352aef4d49439dedd798ac4aef1e7ebef95f569545b647a25338398c1247ffdea",
    "02c05c88cc8fc181b1ba30006df6a4b0597de6490e24514fbdd0266d2b9cd3d0ba",
  ].join(",")
).split(",");
const signingOperators = {};
SO_HOSTS.forEach((address, i) => {
  const identifier = `000000000000000000000000000000000000000000000000000000000000000${i + 1}`;
  signingOperators[identifier] = { id: i, identifier, address: `https://${address}`, identityPublicKey: LOCAL_PUBKEYS[i] };
});

const MNEMONIC_FILE = process.env.SIDECAR_MNEMONIC_FILE ?? "./sidecar.mnemonic";
let mnemonic = process.env.SIDECAR_MNEMONIC ?? "";
if (!mnemonic && fs.existsSync(MNEMONIC_FILE)) mnemonic = fs.readFileSync(MNEMONIC_FILE, "utf8").trim();

const SSP_URL = process.env.SSP_URL ?? "http://127.0.0.1:5000";
let SSP_IDENTITY = process.env.SSP_IDENTITY_PUBKEY ?? "";
if (!SSP_IDENTITY) {
  SSP_IDENTITY = (await (await fetch(`${SSP_URL}/health`)).json()).ssp_identity_pubkey;
}

function baseOpts() {
  return {
    network: NETWORK,
    signingOperators,
    threshold: Number(process.env.SPARK_THRESHOLD ?? "2"),
    // Without this the SDK falls back to a default electrs the container
    // cannot reach, and every claimDeposit fails with "fetch failed".
    electrsUrl: process.env.ELECTRS_URL ?? "http://mempool_electrs:3003",
    sspClientOptions: {
      baseUrl: SSP_URL,
      identityPublicKey: SSP_IDENTITY,
      schemaEndpoint: "graphql/spark/rc",
    },
    optimizationOptions: { auto: false, multiplicity: 0 },
  };
}

let wallet;
if (mnemonic) {
  ({ wallet } = await SparkWallet.initialize({ mnemonicOrSeed: mnemonic, options: baseOpts() }));
} else {
  const created = await SparkWallet.initialize({ options: baseOpts() });
  wallet = created.wallet;
  fs.writeFileSync(MNEMONIC_FILE, created.mnemonic, { mode: 0o600 });
  console.log("generated sidecar mnemonic");
}
console.log("sidecar:", await wallet.getSparkAddress());
// Binary leaf ladder (1000 * 2^n sats, MULTIPLICITY copies each): any
// multiple-of-1000 target sum composes exactly, so sidecar transfers never
// need a swap themselves (no recursion into the SSP). Floor 1000 avoids
// bitcoind dust rejection. Denoms deplete as fills consume them: re-run fund
// to top up (see docs/DEPLOY.md liquidity ops).
const MULTIPLICITY = Number(process.env.FUND_MULTIPLICITY ?? "3");
const DENOMS = (process.env.FUND_LADDER ?? "1000,2000,4000,8000,16000,32000,64000,128000,256000,512000,1024000,2048000,4096000,8192000")
  .split(",").map(BigInt);
const LADDER = DENOMS.flatMap((d) => Array(MULTIPLICITY).fill(d));
const txids = [];
for (const amount of LADDER) {
  const addr = await wallet.getSingleUseDepositAddress();
  const sent = await sendToAddress(addr, amount);
  txids.push(sent.id);
}
console.log(`sent ${txids.length} ladder deposits`);
await mineAndWait(3);
for (const txid of txids) {
  await wallet.claimDeposit(txid);
}
const bal = await wallet.getBalance();
console.log(`funded: ${bal.balance} sats across ladder`);
