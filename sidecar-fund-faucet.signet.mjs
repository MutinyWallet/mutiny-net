// Signet-safe replacement for the sidecar image's /app/faucet.mjs.
//
// The bundled helper is written for regtest: mine() calls generatetoaddress,
// which on MutinyNet's custom signet cannot sign a block (bitcoind-services
// has no signet challenge key) and silently returns []. fund.mjs would then
// wait 4s and try to claim still-unconfirmed deposits.
//
// Here mine(n) instead waits for the miner to produce n real blocks.
const URL = process.env.BITCOIN_RPC_URL ?? "http://127.0.0.1:8332";
const USER = process.env.BITCOIN_RPC_USER ?? "testutil";
const PASS = process.env.BITCOIN_RPC_PASSWORD ?? "testutilpassword";
const WALLET = process.env.BITCOIN_RPC_WALLET ?? "default";

let id = 0;
async function rpc(method, params = [], wallet) {
  const endpoint = wallet ? `${URL}/wallet/${wallet}` : URL;
  const res = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${Buffer.from(`${USER}:${PASS}`).toString("base64")}`,
    },
    body: JSON.stringify({ jsonrpc: "1.0", id: ++id, method, params }),
  });
  const body = await res.json();
  if (body.error) throw new Error(`bitcoind ${method}: ${JSON.stringify(body.error)}`);
  return body.result;
}

export async function sendToAddress(address, sats) {
  const txid = await rpc("sendtoaddress", [address, Number(sats) / 1e8], WALLET);
  return { id: txid };
}

// Wait for n new blocks rather than generating them.
export async function mine(n) {
  const start = await rpc("getblockcount");
  const target = start + n;
  const deadlineMs = Date.now() + 20 * 60 * 1000;
  let last = start;
  while (Date.now() < deadlineMs) {
    const h = await rpc("getblockcount");
    if (h !== last) {
      console.log(`  chain tip ${h} (waiting for ${target})`);
      last = h;
    }
    if (h >= target) return;
    await new Promise((r) => setTimeout(r, 5000));
  }
  throw new Error(`timed out waiting for ${n} blocks from height ${start}`);
}

export async function mineAndWait(n) {
  await mine(n);
  // Chain watcher + SO need a moment to ingest.
  await new Promise((r) => setTimeout(r, 4000));
}
