// Fund exact leaves in the Spark wallet embedded in the SSP.
// Requires Node.js 20+, Bitcoin RPC access, and SPARK_ADMIN_TOKEN.
const SSP_URL = process.env.SSP_URL ?? "http://127.0.0.1:5000";
const RPC_URL = process.env.BITCOIN_RPC_URL ?? "http://127.0.0.1:38335";
const RPC_USER = process.env.BITCOIN_RPC_USER ?? "bitcoin";
const RPC_PASSWORD = process.env.BITCOIN_RPC_PASSWORD ?? process.env.RPCPASSWORD;
const RPC_WALLET = process.env.BITCOIN_RPC_WALLET ?? "default";
const ADMIN_TOKEN = process.env.SPARK_ADMIN_TOKEN ?? "";
const CONFIRMATIONS = Number(process.env.FUND_CONFS ?? "3");
if (!RPC_PASSWORD) throw new Error("set BITCOIN_RPC_PASSWORD or RPCPASSWORD");
if (!ADMIN_TOKEN) throw new Error("set SPARK_ADMIN_TOKEN");

const multiplicity = Number(process.env.FUND_MULTIPLICITY ?? "20");
const denominations = (process.env.FUND_LADDER ??
  "1000,2000,4000,8000,16000,32000,64000")
  .split(",")
  .map(BigInt);
const ladder = denominations.flatMap((value) => Array(multiplicity).fill(value));
let rpcId = 0;

async function rpc(method, params = [], wallet = false) {
  const url = wallet ? `${RPC_URL}/wallet/${encodeURIComponent(RPC_WALLET)}` : RPC_URL;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${RPC_USER}:${RPC_PASSWORD}`).toString("base64")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ jsonrpc: "1.0", id: ++rpcId, method, params }),
  });
  const value = await response.json();
  if (value.error) throw new Error(`${method}: ${JSON.stringify(value.error)}`);
  return value.result;
}

async function admin(path, body) {
  const response = await fetch(`${SSP_URL}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${ADMIN_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const value = await response.json();
  if (!response.ok) throw new Error(value.error ?? `${path}: HTTP ${response.status}`);
  return value;
}

const deposits = [];
for (const amount of ladder) {
  const { address } = await admin("/admin/spark/deposit-address");
  const txid = await rpc("sendtoaddress", [address, Number(amount) / 1e8], true);
  deposits.push({ address, amount, txid });
}
console.log(`sent ${deposits.length} deposits; waiting for confirmations`);

const pending = new Set(deposits.map(({ txid }) => txid));
while (pending.size > 0) {
  for (const txid of pending) {
    try {
      const tx = await rpc("gettransaction", [txid], true);
      if ((tx.confirmations ?? 0) >= CONFIRMATIONS) pending.delete(txid);
    } catch {
      // The transaction is not indexed or confirmed yet.
    }
  }
  if (pending.size > 0) {
    console.log(`${pending.size} deposits still need ${CONFIRMATIONS} confirmations`);
    await new Promise((resolve) => setTimeout(resolve, 15_000));
  }
}

for (const deposit of deposits) {
  const walletTransaction = await rpc("gettransaction", [deposit.txid], true);
  const transaction = await rpc("decoderawtransaction", [walletTransaction.hex]);
  const output = transaction.vout.find(
    ({ scriptPubKey }) =>
      scriptPubKey.address === deposit.address ||
      (scriptPubKey.addresses ?? []).includes(deposit.address),
  );
  if (!output) throw new Error(`deposit output not found in ${deposit.txid}`);
  await admin("/admin/spark/claim-deposit", {
    transaction_hex: walletTransaction.hex,
    vout: output.n,
  });
}

const health = await (await fetch(`${SSP_URL}/health`)).json();
console.log(`SSP Spark balance: ${health.spark.available_sats} sats`);
