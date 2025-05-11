#!/bin/bash
set -Eeuo pipefail

# Maximum allowed age of the latest block (2 hours in seconds)
MAX_AGE=7200

# Function to get the latest block timestamp
get_latest_block_timestamp() {
  local count
  count=$(bitcoin-cli getblockcount 2>/dev/null) || {
    echo "Error: Failed to get block count. Is bitcoind running?" >&2
    return 1
  }
  local hash
  hash=$(bitcoin-cli getblockhash "$count" 2>/dev/null) || {
    echo "Error: Failed to get block hash for block $count" >&2
    return 1
  }
  local timestamp
  timestamp=$(bitcoin-cli getblock "$hash" 2>/dev/null | grep '"time"' | awk '{print $2}' | sed 's/,//g') || {
    echo "Error: Failed to get timestamp for block $hash" >&2
    return 1
  }
  if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid timestamp format: $timestamp" >&2
    return 1
  fi
  echo "$timestamp"
}

# Function to check if the latest block is recent enough
check_block_recency() {
  local timestamp
  timestamp=$(get_latest_block_timestamp) || return 1
  local current_time
  current_time=$(date +%s) || {
    echo "Error: Failed to get current time" >&2
    return 1
  }
  local time_diff=$((current_time - timestamp))
  echo "Latest block timestamp: $timestamp ($(date -d "@$timestamp"))"
  echo "Current time: $current_time ($(date))"
  echo "Time difference: $time_diff seconds"
  if (( time_diff <= MAX_AGE )); then
    echo "Latest block is recent enough (less than 2 hours old). Starting miner..."
    return 0
  else
    echo "Latest block is too old ($time_diff seconds). Waiting..."
    return 1
  fi
}

# Main loop to wait until the block is recent enough
while true; do
  if check_block_recency; then
    echo "Chain tip is recent enough. Proceeding with mining..."
    exit 0
  fi
  echo "Retrying in 30 seconds..."
  sleep 30
done