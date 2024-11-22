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
        function getLatestTransfer(address sender) external view returns (uint256 amount, uint256 timestamp, uint256 nullifier);
    }
}

// Define our journal structure with flattened fields
sol! {
    struct Journal {
        Commitment commitment;
        address from;           // Sender address
        uint256 amount;        // Amount in wei
        uint256 timestamp;     // Block timestamp
        uint256 nullifier;     // Keep as uint256 but ensure proper encoding
    }
}

fn main() {
    // Read inputs from guest environment
    let input: EthEvmInput = env::read();
    let contract_address: Address = env::read();
    let sender: Address = env::read();

    // Convert input into EVM environment
    let env = input.into_env().with_chain_spec(&ETH_SEPOLIA_CHAIN_SPEC);

    let call = IReceiver::getLatestTransferCall { sender };
    let result = Contract::new(contract_address, &env)
        .call_builder(&call)
        .call();
    let min_amount: U256 = "500000000000".parse().unwrap();
    // Check that the given account has made a transfer
    assert!(result.amount >= min_amount);
    assert!(result.nullifier != U256::from(0));

    // Create and commit journal
    let journal = Journal {
        commitment: env.into_commitment(),
        from: sender,
        amount: result.amount,
        timestamp: result.timestamp,
        nullifier: result.nullifier,
    };

    env::commit_slice(&journal.abi_encode());
}

