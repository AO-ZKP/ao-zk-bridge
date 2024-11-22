// File: methods/guest/src/bin/native_transfer.rs

#![no_main]

use alloy_primitives::{Address, U256};
use alloy_sol_types::{sol, SolValue};
use risc0_steel::{
    ethereum::{EthEvmInput, ETH_SEPOLIA_CHAIN_SPEC},
    Commitment, Contract,
};
use risc0_zkvm::guest::env;

risc0_zkvm::guest::entry!(main);

// Interface for our contract that receives ETH
sol! {
    interface IReceiver {
        function getLatestTransfer(address sender) external view returns (uint256 amount, uint256 timestamp);
    }
}

// Define our journal structure with flattened fields
sol! {
    struct Journal {
        Commitment commitment;
        address from;           // Sender address
        uint256 amount;        // Amount in wei
        uint256 timestamp;     // Block timestamp
    }
}

fn main() {
    // Read inputs from guest environment
    let input: EthEvmInput = env::read();
    let contract_address: Address = env::read(); // The address we control/monitor
    let sender_address: Address = env::read(); // The address that sent ETH

    // Convert input into EVM environment
    let env = input.into_env().with_chain_spec(&ETH_SEPOLIA_CHAIN_SPEC);

    let call = IReceiver::getLatestTransferCall {
        sender: sender_address,
    };
    let result = Contract::new(contract_address, &env)
        .call_builder(&call)
        .call();

    // Check that the given account holds at least 1 token.
    assert!(result.amount > U256::from(0));

    // Create and commit journal with flattened fields
    let journal = Journal {
        commitment: env.into_commitment(),
        from: sender_address,
        amount: result.amount,
        timestamp: result.timestamp,
    };

    env::commit_slice(&journal.abi_encode());
}
