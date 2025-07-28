#!/bin/bash

echo "=== Resetting Spark Environment ==="

# Stop the spark container
echo "Stopping spark container..."
docker compose stop spark

# Remove the spark container completely
echo "Removing spark container..."
docker-compose rm -f spark

# Drop the spark database
echo "Dropping spark database..."
docker-compose exec postgres psql -U lightning-rgs -d postgres -c "DROP DATABASE IF EXISTS sparkoperator_0;"

# Recreate the database
echo "Recreating spark database..."
docker-compose exec postgres psql -U lightning-rgs -d postgres -c "CREATE DATABASE sparkoperator_0;"

# Clean up the spark volume
echo "Cleaning spark volume..."
sudo rm -rf ~/volumes/spark/*

# Restart spark container
echo "Starting fresh spark container..."
docker-compose up -d --no-deps --build --force-recreate spark

echo "=== Spark reset complete! ==="
echo "You can monitor the logs with: docker compose logs -f spark"