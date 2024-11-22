#!/bin/bash

# Only cd if we're not already in a directory called steel-app
if [[ "${PWD##*/}" != "steel-app" ]]; then
    cd /home/wings/backend/steel-app
fi

source .env

# Set up environment variable from the local broadcast directory
export RECEIVER_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "ETHReceiver") | .contractAddress' broadcast/DeployReceiver.s.sol/${CHAIN_ID}/run-latest.json)

# Start the server
cargo run --bin transaction -- \
    --eth-rpc-url=$ETH_RPC_URL \
    --receiver-contract=$RECEIVER_ADDRESS \
    --port=$PORT
