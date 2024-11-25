#!/bin/bash

source .env

forge script --rpc-url $ETH_RPC_URL \
    --private-key $ETH_WALLET_PRIVATE_KEY \
    --broadcast \
    DeployReceiver
