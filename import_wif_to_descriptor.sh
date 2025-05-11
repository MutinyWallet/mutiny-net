#!/bin/bash
set -euo pipefail


WIF_PRIVKEY=$(cat ${BITCOIN_DIR}/PRIVKEY.txt)

# Step 1: Construct input descriptor with WIF
#INPUT_DESC="pk($WIF)"
#BASE_DESC="combo($WIF_PRIVKEY)"

BASE_DESC="multi(1,$WIF_PRIVKEY)"
# Step 2: Get checksum (must preserve private key in input, do NOT use returned descriptor)
CHECKSUM=$(bitcoin-cli getdescriptorinfo "$BASE_DESC" | jq -r .checksum)
# Step 3: Final descriptor with checksum
FINAL_DESC="${BASE_DESC}#${CHECKSUM}"
# Step 4: Build import JSON with rescan
IMPORT_JSON=$(cat <<EOF
[{
  "desc": "$FINAL_DESC",
  "timestamp": "now",
  "label": "bdb-migrated-signet"
}]
EOF
)
# Step 5: Import descriptor into wallet
echo "Importing descriptor for signet multisig(1 of 1)..."
bitcoin-cli importdescriptors "$IMPORT_JSON"


BASE_DESC="combo($WIF_PRIVKEY)"
# Step 2: Get checksum (must preserve private key in input, do NOT use returned descriptor)
CHECKSUM=$(bitcoin-cli getdescriptorinfo "$BASE_DESC" | jq -r .checksum)
# Step 3: Final descriptor with checksum
FINAL_DESC="${BASE_DESC}#${CHECKSUM}"
# Step 4: Build import JSON with rescan
IMPORT_JSON=$(cat <<EOF
[{
  "desc": "$FINAL_DESC",
  "timestamp": "now",
  "label": "bdb-migrated-signet"
}]
EOF
)
# Step 5: Import descriptor into wallet
echo "Importing descriptor for signet combo()..."
bitcoin-cli importdescriptors "$IMPORT_JSON"