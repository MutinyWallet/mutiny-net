#!/bin/bash
# Print the operator-derived env for .env:
#   SO_IDENTITY_PUBKEYS  - embedded SSP wallet (comma-separated pubkeys)
# Run after spark/spark2 first boot (keys persist in ~/volumes/spark[N]).
# Re-run after reset-spark.sh: the operator identities are regenerated.
set -euo pipefail

volume_root=$(realpath -m "${MUTINYNET_VOLUME_ROOT:-${HOME}/volumes}")
P0=$(awk -F: '$1 == "PUBLIC" { print $2 }' "$volume_root/spark/keypair_0.txt" 2>/dev/null || true)
P1=$(awk -F: '$1 == "PUBLIC" { print $2 }' "$volume_root/spark2/keypair_1.txt" 2>/dev/null || true)
if [ -z "$P0" ] || [ -z "$P1" ]; then
    echo "Operator keys were not found. Start spark and spark2 first." >&2
    exit 1
fi
if [[ ! "$P0" =~ ^0[23][0-9a-f]{64}$ ]] || \
    [[ ! "$P1" =~ ^0[23][0-9a-f]{64}$ ]]; then
    echo "An operator public key is invalid." >&2
    exit 1
fi

echo "SO_IDENTITY_PUBKEYS=$P0,$P1"
