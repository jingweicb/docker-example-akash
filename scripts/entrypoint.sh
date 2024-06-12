#!/bin/bash
set -euxo pipefail

# debug cmd
#tail -f /dev/null

if [[ "$MODE" = "ONLINE" ]]; then
  if [ ! -d "/data" ]; then
    echo "No /data volume attached"
  fi
fi

if [ -f "/data/config/node_key.json" ]; then
    rm /data/config/node_key.json
    echo "node_key.json removed"
fi

export AKASH_NETWORK=${AKASH_NETWORK:-TESTNET}
export HOME_DIR=${HOME_DIR:-/data}
export CONFIG_PATH=${CONFIG_PATH:-/app/assets}
export NETWORK_ID=${NETWORK_ID:-}
export SNAP_NAME=${SNAP_NAME:-akash_15091720.tar.lz4}  # Update this file name according to polkachu snapshot (https://polkachu.com/snapshots)
# curl -sLo - "https://link.storjshare.io/s/jwavsiqjsbi5xd5qqyv2hir4cosq/sandbox-snapshots/rpc-backup/snapshot.json?download=1" | jq -r '.latest'
export SNAPSHOT_TESTNET="https://link.storjshare.io/s/jxhh2jdzzqr6l2ttbfrfcss5qmza/sandbox-snapshots/rpc-backup/sandbox-01_2024-05-01T05:00:00.tar.gz?download=1"
export SNAP_BASE_URL=${SNAP_BASE_URL:-https://snapshots.polkachu.com/snapshots/akash/}  # Update this file name according to polkachu snapshot (https://polkachu.com/snapshots)
export FROM_SCRATCH=${FROM_SCRATCH:-false}  # if true, remove all data and sync from scratch
export DAEMON_NAME=${DAEMON_HOME:-akash}
#where the cosmovisor/ directory is kept
export DAEMON_HOME=${DAEMON_HOME:-/data}

echo "MODE = $MODE"
echo "AKASH_NETWORK = $AKASH_NETWORK"
echo "HOME_DIR = $HOME_DIR"
echo "NETWORK_ID = $NETWORK_ID"
echo "SNAP_NAME = $SNAP_NAME"
echo "SNAP_BASE_URL = $SNAP_BASE_URL"
echo "CONFIG_PATH = $CONFIG_PATH"
echo "DAEMON_NAME = $DAEMON_NAME"
echo "DAEMON_HOME = $DAEMON_HOME"

# copy akash in docker build to corresponding cosmovisor bin directory
akash_version="$(akash version 2>&1)"
akash_major_version="v0.36.0"

# remove all data if FROM_SCRATCH is true
if [[ "$FROM_SCRATCH" = "true" ]]; then
  echo "from_scatch is true"
  rm -rf $HOME_DIR/*
fi

if [ ! -f "$DAEMON_HOME/cosmovisor/upgrades/$akash_major_version/bin/$DAEMON_NAME" ];then
  echo "creating cosomvisor directory $DAEMON_HOME/cosmovisor/upgrades/$akash_major_version/bin"
  mkdir -p "$DAEMON_HOME/cosmovisor/upgrades/$akash_major_version/bin"
fi

cp "$(which akash)" "$DAEMON_HOME/cosmovisor/upgrades/$akash_major_version/bin"
echo "copied akash($akash_version) binary to $DAEMON_HOME/cosmovisor/upgrades/$akash_major_version/bin/$DAEMON_NAME"

# init akash home if not there
if [ ! -d "$HOME_DIR/config" ]; then
  echo "init akash home"
  akash init "akash-01" --home $HOME_DIR --chain-id $NETWORK_ID -o
fi

# prepare the config
if [[ "$AKASH_NETWORK" = "TESTNET" ]]; then
  echo "prepare the config of $AKASH_NETWORK"
  if [ -f "${HOME_DIR}/config/addrbook.json" ]; then
    echo "addrbook.json file exists. Removing..."
    rm -f "${HOME_DIR}/config/addrbook.json"
    echo "addrbook.json file removed."
  else
    echo "addrbook.json file does not exist."
  fi
  cp /app/assets/app-testnet.toml "$HOME_DIR/config/app.toml"
  cp /app/assets/config-testnet.toml "$HOME_DIR/config/config.toml"
  cp /app/assets/genesis-akash-test.json "$HOME_DIR/config/genesis.json"
elif [[ "$AKASH_NETWORK" = "MAINNET" ]]; then
  echo "prepare the config of $AKASH_NETWORK"
  cp /app/assets/app-mainnet.toml "$HOME_DIR/config/app.toml"
  cp /app/assets/config-mainnet.toml "$HOME_DIR/config/config.toml"
  
  # Download the genesis file for MAINNET
  echo "Downloading genesis file for MAINNET"
  curl -o "$HOME_DIR/config/genesis.json" https://raw.githubusercontent.com/akash-network/net/main/mainnet/genesis.json
fi

# download snapshot if FROM_SCRATCH is true and SNAP_NAME is provided
if [[ "$FROM_SCRATCH" = "true" ]]; then

  # Download and verify snapshot, then extract snapshot
  echo "Downloading snapshot..."

  if [[ "$AKASH_NETWORK" = "TESTNET" ]]; then
    echo "Downloading snapshot from $SNAPSHOT_TESTNET"
#    # we can add -q to wget to make it quiet and save some logs space
    wget -O - "${SNAPSHOT_TESTNET}" | tar xzvf - -C $HOME_DIR/data
  elif [[ "$AKASH_NETWORK" = "MAINNET" ]]; then
    echo "Downloading snapshot from $SNAP_BASE_URL$SNAP_NAME"
    wget -O - "${SNAP_BASE_URL}${SNAP_NAME}" | lz4 -d | tar xvf - -C $HOME_DIR
  fi

  echo "Successfully downloaded snapshot if there is any"
fi

wait

###############
###start node##
###############
if [ ! -L "${DAEMON_HOME}/cosmovisor/current" ]
then
  /usr/local/bin/cosmovisor init /usr/local/bin/akash
fi

echo "start akash"
cosmovisor run start --home "$HOME_DIR"
