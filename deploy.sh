#!/bin/bash


# Load environment variables
source .env

# Default configuration
VERBOSITY="-vvvv"
SCRIPT_PATH="solidity/scripts/XERC20FactoryDeploy.sol:XERC20FactoryDeploy"

for network in binance polygon blast gnosis; do
    echo "\nDeploying to $network..."
    forge script $SCRIPT_PATH \
        --broadcast \
        $VERBOSITY \
        --via-ir \
        --slow \
        --verify \
        --rpc-url $network
done