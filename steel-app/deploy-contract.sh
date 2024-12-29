#!/bin/bash

source .env

forge script --rpc-url $ETH_RPC_URL \
    --private-key $ETH_WALLET_PRIVATE_KEY \
    --broadcast \
    --legacy \
    --skip-simulation \
    DeployReceiver

export RECEIVER_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "ETHReceiver") | .contractAddress' broadcast/DeployReceiver.s.sol/${CHAIN_ID}/run-latest.json)

forge verify-contract --chain-id $CHAIN_ID $RECEIVER_ADDRESS DeployReceiver --verifier-url $VERIFIER_URL_BLOCKSCOUT --verifier blockscout