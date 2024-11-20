use alloy::{providers::ProviderBuilder, sol_types::SolValue};
use alloy_primitives::{Address, U256};
use anyhow::{ensure, Context, Result};
use axum::{
    extract::{Path, State},
    response::Json,
    routing::get,
    Router,
};
use clap::Parser;
use erc20_counter_methods::BALANCE_OF_ELF;
use risc0_ethereum_contracts::encode_seal;
use risc0_steel::{
    ethereum::{EthEvmEnv, ETH_SEPOLIA_CHAIN_SPEC},
    host::BlockNumberOrTag,
    Commitment, Contract,
};
use risc0_zkvm::{default_prover, ExecutorEnv, ProverOpts, VerifierContext};
use serde::Serialize;
use std::{net::SocketAddr, str::FromStr, sync::Arc};
use tokio::task;
use tracing_subscriber::EnvFilter;
use url::Url;

alloy::sol! {
    /// Interface to be called by the guest.
    interface IERC20 {
        function balanceOf(address account) external view returns (uint);
    }

    /// Data committed to by the guest.
    struct Journal {
        Commitment commitment;
        address tokenContract;
        uint256 quantity;
    }
}

#[derive(Parser)]
struct Args {
    /// Ethereum RPC endpoint URL
    #[clap(long, env)]
    eth_rpc_url: Url,

    /// Optional Beacon API endpoint URL
    #[clap(long, env)]
    beacon_api_url: Option<Url>,

    /// Address of the Counter verifier contract
    #[clap(long)]
    counter_address: Address,

    /// Address of the ERC20 token contract
    #[clap(long)]
    token_contract: Address,

    /// Server port to listen on
    #[clap(long, default_value = "3000")]
    port: u16,
}

#[derive(Clone)]
struct AppState {
    eth_rpc_url: Url,
    beacon_api_url: Option<Url>,
    counter_address: Address,
    token_contract: Address,
}

#[derive(Serialize)]
struct ProofResponse {
    receipt: String,
    journal: Vec<u8>,
    seal: Vec<u8>,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

async fn generate_proof(
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
    let account = Address::from_str(&wallet_address).context("Invalid wallet address format")?;

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

    // Prepare the function call
    let call = IERC20::balanceOfCall { account };

    // Preflight the call
    let mut contract = Contract::preflight(state.token_contract, &mut env);
    let returns = contract.call_builder(&call).call().await?._0;
    ensure!(
        returns >= U256::from(1),
        "Account balance must be at least 1"
    );

    // Construct the input
    let evm_input = if let Some(beacon_api_url) = &state.beacon_api_url {
        #[allow(deprecated)]
        env.into_beacon_input(beacon_api_url.clone()).await?
    } else {
        env.into_input().await?
    };

    // Create the steel proof
    let prove_info = task::spawn_blocking(move || {
        let env = ExecutorEnv::builder()
            .write(&evm_input)?
            .write(&state.token_contract)?
            .write(&account)?
            .write(&returns)?
            .build()
            .unwrap();

        default_prover().prove_with_ctx(
            env,
            &VerifierContext::default(),
            BALANCE_OF_ELF,
            &ProverOpts::groth16(),
        )
    })
    .await??;

    let receipt = prove_info.receipt;
    let journal = receipt.journal.bytes.clone();

    // ABI encode the seal
    let seal = encode_seal(&receipt).context("invalid receipt")?;

    Ok(ProofResponse {
        receipt: serde_json::to_string_pretty(&receipt)?,
        journal,
        seal,
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
        beacon_api_url: args.beacon_api_url,
        counter_address: args.counter_address,
        token_contract: args.token_contract,
    });

    // Build the router
    let app = Router::new()
        .route("/generate/:wallet_address", get(generate_proof))
        .with_state(state);

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
