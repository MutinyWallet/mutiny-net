#!/bin/bash
# Print SO identity pubkeys for SO_IDENTITY_PUBKEYS (sidecar env).
# Run after spark/spark2 first boot (keys persist in ~/volumes/spark[N]).
set -e
P0=$(cat ~/volumes/spark/keypair_0.txt 2>/dev/null | grep "PUBLIC:" | cut -d: -f2)
P1=$(cat ~/volumes/spark2/keypair_1.txt 2>/dev/null | grep "PUBLIC:" | cut -d: -f2)
if [ -z "$P0" ] || [ -z "$P1" ]; then
  echo "keys not found; boot spark/spark2 first" >&2
  exit 1
fi
echo "SO_IDENTITY_PUBKEYS=$P0,$P1"
