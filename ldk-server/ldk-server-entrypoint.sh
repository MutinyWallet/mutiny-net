#!/bin/sh
# ldk-server entrypoint: envsubst the config template, then exec.
# Required env: RPCPASSWORD. Optional overrides below.
set -e
: "${LDK_NETWORK:=signet}"
: "${LDK_BITCOIND_HOST:=bitcoind-services:38332}"
: "${LDK_BITCOIND_USER:=bitcoin}"
: "${LDK_ALIAS:=mutinynet-ssp}"
: "${LDK_DATA_DIR:=/home/ldk}"
mkdir -p "$LDK_DATA_DIR"
export LDK_NETWORK LDK_BITCOIND_HOST LDK_BITCOIND_USER LDK_ALIAS LDK_DATA_DIR
envsubst < /config/ldk-server-config.toml > "$LDK_DATA_DIR/ldk-server-config.toml"
exec ldk-server "$LDK_DATA_DIR/ldk-server-config.toml"
