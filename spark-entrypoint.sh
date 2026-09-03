#!/bin/bash
# Spark Operator entrypoint for MutinyNet (2 operators; see SPARK_OPERATOR_COUNT).
# Per-operator state lives in /home/spark (volume ~/volumes/spark[N]).
# Rendezvous between operators happens in /home/spark-shared (shared volume).
set -e

INDEX=${SPARK_INDEX:-0}
# Number of operators. FROST requires min_signers >= 2, so a single-operator
# deployment cannot generate signing keyshares at all (DKG fails with
# InvalidMinSigners) -- 2 is the minimum workable value. Requires the signet
# network-inference patch in spark/Dockerfile; see the comment there.
OPERATOR_COUNT=${SPARK_OPERATOR_COUNT:-2}
THRESHOLD=${SPARK_THRESHOLD:-$OPERATOR_COUNT}
PORT=$((10010 + INDEX))
SOCKET_PATH="/tmp/frost_${INDEX}.sock"
HOME_DIR="/home/spark"
SHARED_DIR="/home/spark-shared"
DB_BASE="postgresql://lightning-rgs:${POSTGRES_PASSWORD}@postgres:5432"
OPERATOR_DB="sparkoperator_${INDEX}"
EPHEMERAL_DB="spark_ephemeral_${INDEX}"

mkdir -p "$HOME_DIR" "$SHARED_DIR" /tmp

wait_for_db() {
    echo "Waiting for database..."
    while ! timeout 5 bash -c "</dev/tcp/postgres/5432" >/dev/null 2>&1; do sleep 2; done
    echo "Database ready"
}

create_databases() {
    for db in "$OPERATOR_DB" "$EPHEMERAL_DB"; do
        echo "Creating database $db (if missing)..."
        PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgres -U lightning-rgs -d postgres \
            -c "CREATE DATABASE $db;" 2>/dev/null || echo "$db exists"
    done
}

run_migrations() {
    echo "Running migrations for $OPERATOR_DB..."
    atlas migrate apply --dir "file:///opt/spark/migrations" \
        --url "postgresql://lightning-rgs:${POSTGRES_PASSWORD}@postgres:5432/${OPERATOR_DB}?sslmode=disable"
    echo "Running ephemeral migrations for $EPHEMERAL_DB..."
    atlas migrate apply --dir "file:///opt/spark/ephemeral_migrations" \
        --url "postgresql://lightning-rgs:${POSTGRES_PASSWORD}@postgres:5432/${EPHEMERAL_DB}?sslmode=disable"
}

ensure_identity() {
    local key_file="$HOME_DIR/operator_${INDEX}.key"
    if [ ! -f "$key_file" ]; then
        echo "Generating operator identity key..."
        python3 /usr/local/bin/keygen.py > "$HOME_DIR/keypair_${INDEX}.txt"
        grep "PRIVATE:" "$HOME_DIR/keypair_${INDEX}.txt" | cut -d: -f2 > "$key_file"
        chmod 600 "$key_file"
    fi
    local pubkey
    pubkey=$(grep "PUBLIC:" "$HOME_DIR/keypair_${INDEX}.txt" | cut -d: -f2)
    echo "$pubkey" > "$SHARED_DIR/pubkey_${INDEX}"
    echo "Operator $INDEX identity: $pubkey"
}

# Both operators publish their pubkeys to the shared volume, then each builds
# the same operators.json. (The old script hardcoded operator 0's pubkey.)
rendezvous_operators() {
    if [ "$OPERATOR_COUNT" = "1" ]; then
        cat > "$HOME_DIR/operators.json" <<EOF
[
  {
    "id": 0,
    "address": "spark:10010",
    "external_address": "spark:10010",
    "identity_public_key": "$(cat "$SHARED_DIR/pubkey_0")",
    "cert_path": "$SHARED_DIR/server_0.crt"
  }
]
EOF
        echo "operators.json ready (single operator)"
        return
    fi
    echo "Waiting for peer operator pubkey + cert..."
    for i in $(seq 1 60); do
        if [ -f "$SHARED_DIR/pubkey_0" ] && [ -f "$SHARED_DIR/pubkey_1" ] \
        && [ -f "$SHARED_DIR/server_0.crt" ] && [ -f "$SHARED_DIR/server_1.crt" ]; then break; fi
        sleep 2
    done
    if [ ! -f "$SHARED_DIR/pubkey_0" ] || [ ! -f "$SHARED_DIR/pubkey_1" ]; then
        echo "ERROR: peer pubkey did not appear in $SHARED_DIR"
        exit 1
    fi
    if [ ! -f "$SHARED_DIR/server_0.crt" ] || [ ! -f "$SHARED_DIR/server_1.crt" ]; then
        echo "ERROR: peer cert did not appear in $SHARED_DIR"
        exit 1
    fi
    local pub0 pub1
    pub0=$(cat "$SHARED_DIR/pubkey_0"); pub1=$(cat "$SHARED_DIR/pubkey_1")
    cat > "$HOME_DIR/operators.json" <<EOF
[
  {
    "id": 0,
    "address": "spark:10010",
    "external_address": "spark:10010",
    "identity_public_key": "$pub0",
    "cert_path": "$SHARED_DIR/server_0.crt"
  },
  {
    "id": 1,
    "address": "spark2:10011",
    "external_address": "spark2:10011",
    "identity_public_key": "$pub1",
    "cert_path": "$SHARED_DIR/server_1.crt"
  }
]
EOF
    echo "operators.json ready"
}

ensure_tls_cert() {
    if [ -f "$HOME_DIR/server.crt" ] && [ -f "$HOME_DIR/server.key" ]; then
        echo "TLS cert exists"
    else
        echo "Generating TLS cert..."
        openssl genrsa -out "$HOME_DIR/server.key" 2048 2>/dev/null
        openssl req -new -x509 -key "$HOME_DIR/server.key" -out "$HOME_DIR/server.crt" \
            -days 3650 -subj "/CN=spark-$INDEX" \
            -addext "subjectAltName = DNS:spark,DNS:spark2,DNS:localhost,DNS:spark.minikube.local,DNS:spark2.minikube.local,DNS:0.spark.mutinynet.com,DNS:1.spark.mutinynet.com"
    fi
    # Publish our cert to the shared volume. Each operator's cert is self-signed,
    # so the peer must trust *that* file directly -- pointing both operators at
    # their own server.crt makes DKG fail with "certificate signed by unknown
    # authority".
    cp "$HOME_DIR/server.crt" "$SHARED_DIR/server_${INDEX}.crt"
}

start_frost_signer() {
    echo "Starting frost signer on $SOCKET_PATH..."
    spark-frost-signer -u "$SOCKET_PATH" &
    SIGNER_PID=$!
    for i in $(seq 1 30); do
        [ -S "$SOCKET_PATH" ] && break
        kill -0 "$SIGNER_PID" 2>/dev/null || { echo "Frost signer died"; exit 1; }
        sleep 1
    done
    [ -S "$SOCKET_PATH" ] || { echo "Frost signer socket timeout"; exit 1; }
}

cleanup() {
    [ -n "$SIGNER_PID" ] && kill "$SIGNER_PID" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "=== Spark operator $INDEX ==="
wait_for_db
create_databases
run_migrations
ensure_identity
# Must precede rendezvous: it publishes our cert, which the peer waits for.
ensure_tls_cert
rendezvous_operators
[ -f /config/so_config.yaml ] && envsubst < /config/so_config.yaml > "$HOME_DIR/so_config.yaml"
start_frost_signer

echo "Starting spark-operator on port $PORT..."
exec spark-operator \
    -config "$HOME_DIR/so_config.yaml" \
    -index "$INDEX" \
    -key "$HOME_DIR/operator_${INDEX}.key" \
    -operators "$HOME_DIR/operators.json" \
    -threshold "$THRESHOLD" \
    -signer "unix://$SOCKET_PATH" \
    -port "$PORT" \
    -database "${DB_BASE}/${OPERATOR_DB}?sslmode=disable" \
    -ephemeral-database "${DB_BASE}/${EPHEMERAL_DB}?sslmode=disable" \
    -server-cert "$HOME_DIR/server.crt" \
    -server-key "$HOME_DIR/server.key" \
    -supported-networks signet \
    -local
