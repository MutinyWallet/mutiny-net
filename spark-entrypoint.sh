#!/bin/bash
# Spark Operator entrypoint for the two MutinyNet operators.
# Per-operator state lives in /home/spark (volume ~/volumes/spark[N]).
# Rendezvous between operators happens in /home/spark-shared (shared volume).
set -euo pipefail

INDEX=${SPARK_INDEX:-0}
case "$INDEX" in
    0|1) ;;
    *) echo "ERROR: SPARK_INDEX must be 0 or 1" >&2; exit 1 ;;
esac
THRESHOLD=2
PORT=$((10010 + INDEX))
SSP_PORT=$((11010 + INDEX))
SOCKET_PATH="/tmp/frost_${INDEX}.sock"
HOME_DIR="/home/spark"
SHARED_DIR="/home/spark-shared"
DB_BASE="postgresql://lightning-rgs:${POSTGRES_PASSWORD}@postgres:5432"
OPERATOR_DB="sparkoperator_${INDEX}"
EPHEMERAL_DB="spark_ephemeral_${INDEX}"
SIGNER_PID=""

mkdir -p "$HOME_DIR" "$SHARED_DIR" /tmp

wait_for_db() {
    echo "Waiting for database..."
    while ! timeout 5 bash -c "</dev/tcp/postgres/5432" >/dev/null 2>&1; do sleep 2; done
    echo "Database ready"
}

create_databases() {
    for db in "$OPERATOR_DB" "$EPHEMERAL_DB"; do
        if PGPASSWORD="$POSTGRES_PASSWORD" psql \
            -h postgres -U lightning-rgs -d postgres -tAc \
            "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1; then
            echo "Database $db exists"
        else
            echo "Creating database $db..."
            PGPASSWORD="$POSTGRES_PASSWORD" createdb \
                -h postgres -U lightning-rgs "$db"
        fi
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
    local keypair_file="$HOME_DIR/keypair_${INDEX}.txt"
    if [ ! -f "$key_file" ] && [ ! -f "$keypair_file" ]; then
        echo "Generating operator identity key..."
        python3 /usr/local/bin/keygen.py > "$keypair_file"
        grep "PRIVATE:" "$keypair_file" | cut -d: -f2 > "$key_file"
        chmod 600 "$key_file"
    elif [ ! -f "$key_file" ] || [ ! -f "$keypair_file" ]; then
        echo "ERROR: incomplete operator identity in $HOME_DIR" >&2
        echo "Run ./reset-spark.sh to create a consistent identity." >&2
        exit 1
    fi
    local pubkey
    pubkey=$(grep "PUBLIC:" "$keypair_file" | cut -d: -f2)
    if [ -z "$pubkey" ]; then
        echo "ERROR: operator public key is empty" >&2
        exit 1
    fi
    echo "$pubkey" > "$SHARED_DIR/pubkey_${INDEX}"
    echo "Operator $INDEX identity: $pubkey"
}

# Both operators publish their pubkeys to the shared volume, then each builds
# the same operators.json. (The old script hardcoded operator 0's pubkey.)
rendezvous_operators() {
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
    local cert="$HOME_DIR/server.crt"
    local key="$HOME_DIR/server.key"
    local tmp_cert="${cert}.tmp"
    local tmp_key="${key}.tmp"
    if [ -f "$cert" ] && [ -f "$key" ] \
    && openssl x509 -in "$cert" -noout -ext basicConstraints 2>/dev/null \
        | grep -q "CA:FALSE"; then
        echo "TLS server cert exists"
    else
        if [ -f "$cert" ] && [ -f "$key" ]; then
            echo "Rotating legacy CA-marked TLS cert..."
            [ -f "${cert}.legacy-ca" ] || cp -p "$cert" "${cert}.legacy-ca"
            [ -f "${key}.legacy-ca" ] || cp -p "$key" "${key}.legacy-ca"
        else
            echo "Generating TLS server cert..."
        fi
        openssl genrsa -out "$tmp_key" 2048 2>/dev/null
        openssl req -new -x509 -key "$tmp_key" -out "$tmp_cert" \
            -days 3650 -subj "/CN=spark-$INDEX" \
            -addext "subjectAltName = DNS:spark,DNS:spark2,DNS:localhost,DNS:spark.minikube.local,DNS:spark2.minikube.local,DNS:0.spark.mutinynet.com,DNS:1.spark.mutinynet.com" \
            -addext "basicConstraints = critical,CA:FALSE" \
            -addext "keyUsage = critical,digitalSignature,keyEncipherment" \
            -addext "extendedKeyUsage = serverAuth"
        mv "$tmp_key" "$key"
        mv "$tmp_cert" "$cert"
    fi
    # Publish our cert to the shared volume. Each operator's cert is self-signed,
    # so the peer must trust *that* file directly -- pointing both operators at
    # their own server.crt makes DKG fail with "certificate signed by unknown
    # authority".
    cp "$cert" "$SHARED_DIR/server_${INDEX}.crt.tmp"
    mv "$SHARED_DIR/server_${INDEX}.crt.tmp" \
        "$SHARED_DIR/server_${INDEX}.crt"
}

start_frost_signer() {
    echo "Starting frost signer on $SOCKET_PATH..."
    rm -f "$SOCKET_PATH"
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
    if [ -n "$SIGNER_PID" ]; then
        kill "$SIGNER_PID" 2>/dev/null || true
    fi
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
if [ ! -f /config/so_config.yaml ]; then
    echo "ERROR: /config/so_config.yaml does not exist" >&2
    exit 1
fi
envsubst '${RPCPASSWORD}' < /config/so_config.yaml > "$HOME_DIR/so_config.yaml"
start_frost_signer

echo "Starting spark-operator on public port $PORT and SSP-only port $SSP_PORT..."
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
    -ssp-grpc-port "$SSP_PORT" \
    -supported-networks signet
