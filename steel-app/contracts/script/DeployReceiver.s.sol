// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ETHReceiver} from "../src/ETHReceiver.sol";

/// @notice Deployment script for the ETHReceiver contract.
/// @dev Use ETH_WALLET_PRIVATE_KEY environment variable for deployment
contract DeployReceiver is Script {
    function run() external {
        // Get the private key from environment variable
        uint256 deployerKey = uint256(vm.envBytes32("ETH_WALLET_PRIVATE_KEY"));

        // Start broadcasting transactions
        vm.startBroadcast(deployerKey);

        // Deploy the ETHReceiver contract
        ETHReceiver receiver = new ETHReceiver();
        console2.log("Deployed ETHReceiver to", address(receiver));
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
