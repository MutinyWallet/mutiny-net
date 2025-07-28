#!/bin/bash
set -e

echo "=== Starting Spark Services ==="

# Create socket directory
mkdir -p /tmp

# Create data directory for spark user
mkdir -p /home/spark/data
chown spark:spark /home/spark/data

# Function to wait for database to be ready
wait_for_db() {
    echo "Waiting for database to be ready..."
    until atlas migrate status --url "$DATABASE_URL" >/dev/null 2>&1; do
        echo "Database not ready, waiting..."
        sleep 2
    done
    echo "Database is ready!"
}

# Function to run database migrations
run_migrations() {
    echo "Running database migrations..."
    atlas migrate apply --dir "file:///opt/spark/migrations" --url "$DATABASE_URL"
    echo "Database migrations completed!"
}

# Function to start frost signer
start_frost_signer() {
    echo "Starting Frost signer..."
    spark-frost-signer -u /tmp/frost_0.sock &
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

# Function to start spark operator
start_spark_operator() {
    echo "Starting Spark operator..."
    exec spark-operator \
        -config /config/so_config.yaml \
        -index 0 \
        -port 10009 \
        -db "$DATABASE_URL" \
        -signer-socket unix:///tmp/frost_0.sock
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
run_migrations

# Start services
start_frost_signer
start_spark_operator