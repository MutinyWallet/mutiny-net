#!/bin/bash

echo "=== Resetting Spark Environment ==="

# Stop both spark containers
echo "Stopping spark containers..."
docker compose stop spark spark2

# Remove both spark containers completely
echo "Removing spark containers..."
docker-compose rm -f spark spark2

# Drop both spark databases
echo "Dropping spark databases..."
docker-compose exec postgres psql -U lightning-rgs -d postgres -c "DROP DATABASE IF EXISTS sparkoperator_0;"
docker-compose exec postgres psql -U lightning-rgs -d postgres -c "DROP DATABASE IF EXISTS sparkoperator_1;"

# Recreate both databases
echo "Recreating spark databases..."
docker-compose exec postgres psql -U lightning-rgs -d postgres -c "CREATE DATABASE sparkoperator_0;"
docker-compose exec postgres psql -U lightning-rgs -d postgres -c "CREATE DATABASE sparkoperator_1;"

# Clean up both spark volumes
echo "Cleaning spark volumes..."
sudo rm -rf ~/volumes/spark/*
sudo rm -rf ~/volumes/spark2/*

# Restart both spark containers
echo "Starting fresh spark containers..."
docker-compose up -d --no-deps --build --force-recreate spark spark2

echo "=== Spark reset complete! ==="
echo "You can monitor the logs with: docker compose logs -f spark spark2"