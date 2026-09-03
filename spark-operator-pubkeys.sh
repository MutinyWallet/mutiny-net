#!/bin/bash
# Print the operator-derived env for .env:
#   SO_IDENTITY_PUBKEYS  - swap sidecar (comma-separated pubkeys)
#   SSP_FROST_OPERATORS  - SSP (JSON; used to encrypt preimage shares per SO)
#   SSP_FROST_THRESHOLD  - SSP (must be >= 2)
# Run after spark/spark2 first boot (keys persist in ~/volumes/spark[N]).
# Re-run after reset-spark.sh: the operator identities are regenerated.
set -e
P0=$(cat ~/volumes/spark/keypair_0.txt 2>/dev/null | grep "PUBLIC:" | cut -d: -f2)
P1=$(cat ~/volumes/spark2/keypair_1.txt 2>/dev/null | grep "PUBLIC:" | cut -d: -f2)
if [ -z "$P0" ] || [ -z "$P1" ]; then
  echo "keys not found; boot spark/spark2 first" >&2
  exit 1
fi

ID0="0000000000000000000000000000000000000000000000000000000000000001"
ID1="0000000000000000000000000000000000000000000000000000000000000002"
ADDR0="${SPARK_OPERATOR_0_ADDRESS:-https://0.spark.mutinynet.com}"
ADDR1="${SPARK_OPERATOR_1_ADDRESS:-https://1.spark.mutinynet.com}"

echo "SO_IDENTITY_PUBKEYS=$P0,$P1"
printf 'SSP_FROST_OPERATORS=[{"id":0,"identifier":"%s","address":"%s","identityPublicKey":"%s"},{"id":1,"identifier":"%s","address":"%s","identityPublicKey":"%s"}]\n' \
  "$ID0" "$ADDR0" "$P0" "$ID1" "$ADDR1" "$P1"
echo "SSP_FROST_THRESHOLD=2"
