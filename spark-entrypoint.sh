#!/bin/bash
set -e

echo "=== Starting Spark Services ==="

# Install required packages if not present
if ! python3 -c "import ecdsa" 2>/dev/null || ! command -v psql >/dev/null; then
    echo "Installing required packages..."
    apt-get update -qq
    apt-get install -y python3-ecdsa postgresql-client
fi

# Create socket directory
mkdir -p /tmp

# Create data directory
mkdir -p /home/spark/data

# Function to wait for database to be ready
wait_for_db() {
    echo "Waiting for database to be ready..."
    # Simple approach: try to connect to the database
    while ! timeout 5 bash -c "</dev/tcp/postgres/5432" >/dev/null 2>&1; do
        echo "Database not ready, waiting..."
        sleep 2
    done
    echo "Database connection is ready!"
}

# Function to create operator database
create_operator_database() {
    echo "Creating operator database..."
    # Extract database name from URL for creation
    local db_name=$(echo "$DATABASE_URL" | sed 's/.*\/\([^?]*\).*/\1/')
    local base_url=$(echo "$DATABASE_URL" | sed 's/\/[^\/]*?/\/postgres?/')

    echo "Creating database: $db_name"
    # Use psql to create the database if it doesn't exist
    PGPASSWORD=docker psql -h postgres -U lightning-rgs -d postgres -c "CREATE DATABASE $db_name;" 2>/dev/null || echo "Database may already exist"
    echo "Database creation completed!"
}

# Function to run database migrations
run_migrations() {
    echo "Running database migrations..."
    atlas migrate apply --dir "file:///opt/spark/migrations" --url "$DATABASE_URL"
    echo "Database migrations completed!"
}

# Function to start frost signer
start_frost_signer() {
    local index=${SPARK_INDEX:-0}
    local signer_socket="/tmp/frost_${index}.sock"
    
    echo "Starting Frost signer..."
    echo "Signer socket: $signer_socket"
    spark-frost-signer -u $signer_socket &
    SIGNER_PID=$!
    echo "Frost signer started with PID: $SIGNER_PID"
    
    # Wait a moment for signer to start
    sleep 2
    
    # Check if signer is still running
    if ! kill -0 $SIGNER_PID 2>/dev/null; then
        echo "ERROR: Frost signer failed to start"
        exit 1
    fi
}

# Function to create identity key and operators config
create_identity_and_config() {
    local index=${SPARK_INDEX:-0}
    local key_file="/home/spark/operator_${index}.key"
    local operators_file="/home/spark/operators.json"
    local keypair_file="/home/spark/keypair_${index}.txt"
    
    if [ ! -f "$keypair_file" ]; then
        echo "Generating new secp256k1 key pair..."
        echo "Testing keygen.py script..."
        python3 /usr/local/bin/keygen.py 2>&1 | tee "$keypair_file"
        local exit_code=$?
        echo "Keygen exit code: $exit_code"
        if [ $exit_code -ne 0 ]; then
            echo "ERROR: Failed to generate key pair"
            echo "Keygen output:"
            cat "$keypair_file"
            exit 1
        fi
        echo "New key pair generated"
    else
        echo "Using existing key pair"
    fi
    
    # Debug: show contents of keypair file
    echo "Contents of keypair file:"
    cat "$keypair_file"

    # Extract keys from generated file
    local private_key=$(grep "PRIVATE:" "$keypair_file" | cut -d: -f2)
    local public_key=$(grep "PUBLIC:" "$keypair_file" | cut -d: -f2)
    
    echo "Extracted private key: '$private_key'"
    echo "Extracted public key: '$public_key'"
    
    if [ -z "$private_key" ] || [ -z "$public_key" ]; then
        echo "ERROR: Failed to extract keys from keypair file"
        echo "Keypair file contents:"
        cat "$keypair_file"
        exit 1
    fi
    
    # Create private key file
    echo "$private_key" > "$key_file"
    chmod 600 "$key_file"
    
    echo "Creating operators configuration..."
    if [ "$index" = "0" ]; then
        # Generate second operator's key for the JSON (using a different seed)
        local public_key_2=$(python3 /usr/local/bin/keygen.py | grep "PUBLIC:" | cut -d: -f2)
        cat > "$operators_file" << EOF
[
  {
    "id": 0,
    "address": "0.0.0.0:10009",
    "external_address": "spark:10009",
    "address_dkg": "spark:10009",
    "identity_public_key": "$public_key"
  },
  {
    "id": 1,
    "address": "0.0.0.0:10010",
    "external_address": "spark2:10010", 
    "address_dkg": "spark2:10010",
    "identity_public_key": "$public_key_2"
  }
]
EOF
    else
        # For operator 1, create the same operators.json with both operators
        # But we need to read operator 0's public key from shared config
        cat > "$operators_file" << EOF
[
  {
    "id": 0,
    "address": "0.0.0.0:10009",
    "external_address": "spark:10009",
    "address_dkg": "spark:10009", 
    "identity_public_key": "0322ca18fc489ae25418a0e768273c2c61cabb823edfb14feb891e9bec62016510"
  },
  {
    "id": 1,
    "address": "0.0.0.0:10010", 
    "external_address": "spark2:10010",
    "address_dkg": "spark2:10010",
    "identity_public_key": "$public_key"
  }
]
EOF
    fi
    echo "Operators config created"
}

# Function to create final config with substitutions
create_final_config() {
    local final_config="/home/spark/so_config.yaml"
    echo "Creating final config with environment substitutions..."
    
    # Replace environment variables in config
    envsubst < /config/so_config.yaml > "$final_config"
    echo "Final config created at $final_config"
}

# Function to start spark operator
start_spark_operator() {
    local index=${SPARK_INDEX:-0}
    local port=$((10009 + index))
    local key_file="/home/spark/operator_${index}.key"
    local signer_socket="unix:///tmp/frost_${index}.sock"
    
    echo "Starting Spark operator..."
    echo "Operator index: $index"
    echo "Port: $port"
    echo "Database URL being passed: '$DATABASE_URL'"
    echo "Database URL starts with postgresql: $(echo "$DATABASE_URL" | grep -q "^postgresql" && echo "YES" || echo "NO")"
    echo "Config file database section:"
    grep -A 10 "database:" /home/spark/so_config.yaml
    
    echo "Starting with command:"
    echo "spark-operator -config /home/spark/so_config.yaml -index $index -port $port -database '$DATABASE_URL' -signer $signer_socket -key $key_file -operators /home/spark/operators.json -threshold 2 -supported-networks regtest -local -log-level debug"
    
    exec spark-operator \
        -config /home/spark/so_config.yaml \
        -index $index \
        -port $port \
        -database "$DATABASE_URL" \
        -signer $signer_socket \
        -key $key_file \
        -operators /home/spark/operators.json \
        -threshold 2 \
        -supported-networks regtest \
        -local \
        -log-level debug
}

# Function to cleanup on exit
cleanup() {
    echo "Shutting down services..."
    if [ ! -z "$SIGNER_PID" ]; then
        kill $SIGNER_PID 2>/dev/null || true
    fi
    exit 0
}

# Set up signal handling
trap cleanup SIGTERM SIGINT

# Main execution
echo "DATABASE_URL: $DATABASE_URL"

# Wait for database and run migrations
wait_for_db
create_operator_database
run_migrations

# Start services
create_identity_and_config
create_final_config
start_frost_signer
start_spark_operator