#!/bin/bash
# Delete the Spark, SSP, and sidecar state. LDK data is kept by default.
set -euo pipefail

cd "$(dirname "$0")"

full=0
assume_yes=0
for arg in "$@"; do
    case "$arg" in
        --full) full=1 ;;
        --yes) assume_yes=1 ;;
        -h|--help)
            echo "Usage: $0 [--full] [--yes]"
            echo "  --full  Also delete the LDK wallet and channel state."
            echo "  --yes   Do not ask for confirmation."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

volume_root=$(realpath -m "${MUTINYNET_VOLUME_ROOT:-${HOME}/volumes}")
case "$volume_root" in
    /|"$HOME")
        echo "Refusing unsafe volume root: $volume_root" >&2
        exit 1
        ;;
esac

targets=(spark spark2 spark-shared ssp-data sidecar-data)
if [ "$full" = "1" ]; then
    targets+=(ldk-server)
fi

echo "This deletes state from:"
for name in "${targets[@]}"; do
    echo "  $volume_root/$name"
done
if [ "$assume_yes" != "1" ]; then
    read -r -p "Type RESET to continue: " confirmation
    if [ "$confirmation" != "RESET" ]; then
        echo "Reset cancelled"
        exit 1
    fi
fi

services=(spark spark2 ssp swap-sidecar)
if [ "$full" = "1" ]; then
    services+=(ldk-server)
fi
docker compose stop "${services[@]}" || true

for db in \
    sparkoperator_0 spark_ephemeral_0 \
    sparkoperator_1 spark_ephemeral_1; do
    docker compose exec -T postgres psql \
        -U lightning-rgs -d postgres \
        -c "DROP DATABASE IF EXISTS $db;"
done

for name in "${targets[@]}"; do
    target="$volume_root/$name"
    mkdir -p "$target"
    resolved=$(realpath -m "$target")
    if [ "$resolved" != "$target" ] || \
        [ "${resolved#"$volume_root"/}" = "$resolved" ]; then
        echo "Refusing unexpected reset target: $resolved" >&2
        exit 1
    fi
    find "$resolved" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
done

docker compose up -d --no-deps --force-recreate spark spark2

echo "Spark operators are starting with new identities."
echo "After both are healthy:"
echo "  1. Run ./spark-operator-pubkeys.sh and update .env."
echo "  2. Run docker compose up -d ldk-server ssp swap-sidecar."
echo "  3. Run docker compose run --rm sidecar-fund."
