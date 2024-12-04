// File: apps/src/bin/transaction.rs

use alloy::{providers::ProviderBuilder, sol_types::SolValue};
use alloy_primitives::{Address, U256};
use anyhow::{ensure, Context, Result};
use axum::{
    extract::{Path, State},
    response::Json,
    routing::get,
    Router,
};
use http::{HeaderValue, Method};
use clap::Parser;
use erc20_counter_methods::TX_INFO_ELF;
use risc0_ethereum_contracts::encode_seal;
use risc0_steel::{
    ethereum::{EthEvmEnv, ETH_SEPOLIA_CHAIN_SPEC},
    host::BlockNumberOrTag,
    Commitment, Contract,
};
use risc0_zkvm::{default_prover, ExecutorEnv, ProverOpts, VerifierContext, Receipt};
use serde::Serialize;
use std::{net::SocketAddr, str::FromStr, sync::Arc};
use tokio::task;
use tower_http::cors::{Any, CorsLayer};
use tracing_subscriber::EnvFilter;
use url::Url;

alloy::sol! {
    /// Interface to be called by the guest.
    interface IReceiver {
        function getLatestTransfer(address sender) external view returns (uint256 amount, uint256 timestamp, uint256 nullifier);
    }

    /// Data committed to by the guest.
    struct Journal {
        Commitment commitment;
        address from;
        uint256 amount;
        uint256 timestamp;
        uint256 nullifier;
    }
}

#[derive(Parser)]
struct Args {
    /// Ethereum RPC endpoint URL
    #[clap(long, env)]
    eth_rpc_url: Url,

    /// Address of the receiver contract
    #[clap(long)]
    receiver_contract: Address,

    /// Server port to listen on
    #[clap(long, default_value = "3000")]
    port: u16,
}

#[derive(Clone)]
struct AppState {
    eth_rpc_url: Url,
    receiver_contract: Address,
}

#[derive(Serialize)]
struct ProofResponse {
    receipt: Receipt,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    version: String,
}

async fn health_check() -> Json<HealthResponse> {
    log::info!("Health check");
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

async fn generate_transfer_proof(
    State(state): State<Arc<AppState>>,
    Path(wallet_address): Path<String>,
) -> Json<Result<ProofResponse, ErrorResponse>> {
    match generate_proof_internal(state, wallet_address).await {
        Ok(response) => Json(Ok(response)),
        Err(e) => Json(Err(ErrorResponse {
            error: e.to_string(),
        })),
    }
}

async fn generate_proof_internal(
    state: Arc<AppState>,
    wallet_address: String,
) -> Result<ProofResponse> {
    let sender = Address::from_str(&wallet_address).context("Invalid wallet address format")?;
    log::debug!("Processing proof for sender: {}", sender);
    // Create an alloy provider
    let provider = ProviderBuilder::new()
        .with_recommended_fillers()
        .on_http(state.eth_rpc_url.clone());

    // Create an EVM environment
    let mut env = EthEvmEnv::builder()
        .provider(provider.clone())
        .block_number_or_tag(BlockNumberOrTag::Parent)
        .build()
        .await?;
    env = env.with_chain_spec(&ETH_SEPOLIA_CHAIN_SPEC);

    // Prepare the function call for preflight
    let call = IReceiver::getLatestTransferCall { sender };

    log::debug!(
        "Preflighting call for contract: {}",
        state.receiver_contract
    );
    // Preflight the call
    let mut contract = Contract::preflight(state.receiver_contract, &mut env);
    let returns = contract.call_builder(&call).call().await?;
    log::debug!(
        "Transfer details - Amount: {}, Timestamp: {}, Nullifier: {}",
        returns.amount,
        returns.timestamp,
        returns.nullifier
    );
    let min_amount: U256 = "500000000000".parse().unwrap();
    ensure!(
        returns.amount >= min_amount,
        "No sufficient transfers found for this address"
    );

    ensure!(
        returns.nullifier != U256::ZERO,
        "Nullifier is zero, invalid transfer"
    );

    // Construct the input
    let evm_input = env.into_input().await?;
    

    // Create the steel proof
    let prove_info = task::spawn_blocking(move || {
        let env = ExecutorEnv::builder()
            .write(&evm_input)?
            .write(&state.receiver_contract)?
            .write(&sender)?
            .build()
            .unwrap();

        default_prover().prove_with_ctx(
            env,
            &VerifierContext::default(),
            TX_INFO_ELF,
            &ProverOpts::groth16(),
        )
    })
    .await??;

    let receipt = prove_info.receipt;
    let journal = &receipt.journal.bytes;

    // Decode and log the commitment
    let journal = Journal::abi_decode(journal, true).context("invalid journal")?;
    log::info!("Journal details:");
    log::info!("Steel commitment: {:?}", journal.commitment);
    log::info!("From Address: {}", journal.from);
    log::info!("Amount: {}", journal.amount);
    log::info!("Timestamp: {}", journal.timestamp);
    log::info!("Nullifier: {}", journal.nullifier);

    // ABI encode the seal
    let _seal = encode_seal(&receipt).context("invalid receipt")?;

    Ok(ProofResponse {
        receipt: receipt,
    })
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    // Parse command line arguments
    let args = Args::parse();

    // Create the shared application state
    let state = Arc::new(AppState {
        eth_rpc_url: args.eth_rpc_url,
        receiver_contract: args.receiver_contract,
    });

    // Configure CORS
    let cors = CorsLayer::new()
        .allow_origin(vec![
            "http://localhost:5173".parse::<HeaderValue>().unwrap(),
            "https://bridge_a0labs.arweave.net".parse::<HeaderValue>().unwrap(),
            "https://a0labs.arweave.net".parse::<HeaderValue>().unwrap(),
            "https://a0labs_arlink.ar-io.dev".parse::<HeaderValue>().unwrap(),
            "https://ao-zk-bridge_arlink.ar-io.dev".parse::<HeaderValue>().unwrap(), 
        ])
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers(Any);    

    // Build the router
    let app = Router::new()
        .route("/", get(health_check))
        .route("/generate/:wallet_address", get(generate_transfer_proof))
        .with_state(state)
        .layer(cors);

    // Create the server address
    let addr = SocketAddr::from(([127, 0, 0, 1], args.port));
    println!("Server listening on {}", addr);

    // Start the server
    axum::serve(
        tokio::net::TcpListener::bind(addr).await?,
        app.into_make_service(),
    )
    .await?;

    Ok(())
}

