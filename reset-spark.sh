#!/bin/bash
# Reset the Spark + SSP stack (operators, SSP state, sidecar). LDK node data
# is preserved unless --full is passed (backs up nothing; use with care).
set -e
cd "$(dirname "$0")"

FULL=0
[ "$1" = "--full" ] && FULL=1

echo "=== Resetting Spark environment ==="

echo "Stopping spark containers..."
docker compose stop spark spark2 ssp swap-sidecar || true

echo "Dropping spark databases..."
docker compose exec postgres psql -U lightning-rgs -d postgres -c "DROP DATABASE IF EXISTS sparkoperator_0;" || true
docker compose exec postgres psql -U lightning-rgs -d postgres -c "DROP DATABASE IF EXISTS spark_ephemeral_0;" || true
docker compose exec postgres psql -U lightning-rgs -d postgres -c "DROP DATABASE IF EXISTS sparkoperator_1;" || true
docker compose exec postgres psql -U lightning-rgs -d postgres -c "DROP DATABASE IF EXISTS spark_ephemeral_1;" || true

echo "Recreating spark databases..."
for db in sparkoperator_0 spark_ephemeral_0 sparkoperator_1 spark_ephemeral_1; do
  docker compose exec postgres psql -U lightning-rgs -d postgres -c "CREATE DATABASE $db;"
done

echo "Cleaning operator + SSP volumes..."
sudo rm -rf ~/volumes/spark/* ~/volumes/spark2/* ~/volumes/spark-shared/* \
  ~/volumes/ssp-data/* ~/volumes/sidecar-data/*

if [ "$FULL" = "1" ]; then
  echo "Full reset: also clearing ldk-server data (channels + wallet)..."
  docker compose stop ldk-server || true
  sudo rm -rf ~/volumes/ldk-server/*
fi

echo "Starting fresh..."
docker compose up -d --no-deps --force-recreate spark spark2
echo "Next: ssp (generates fresh signing key), then fund sidecar:"
echo "  docker compose up -d --no-deps ssp swap-sidecar"
echo "  docker compose run --rm sidecar-fund"
echo "Monitor: docker compose logs -f spark spark2 ssp"
