#!/bin/bash

source .env

forge script --rpc-url http://localhost:8545 \
    --private-key $ETH_WALLET_PRIVATE_KEY \
    --broadcast \
    DeployReceiver
