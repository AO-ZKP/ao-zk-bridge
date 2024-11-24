import { readFileSync } from "node:fs";
import { message, createDataItemSigner } from "@permaweb/aoconnect/node";
import { createPublicClient, http } from "viem";
import { sepolia, foundry } from "viem/chains";
import "dotenv/config";

// const { message } = connect(
//   {
//     MU_URL: "https://ao-mu-1.onrender.com",
//     CU_URL: "https://cu.ao-testnet.xyz",
//     GATEWAY_URL: "https://arweave.net",
//   },
// );

// Environment configuration
const ENV = process.env.NODE_ENV || "local";
const ANVIL_PORT = process.env.ANVIL_PORT || "8545";



const wallet = JSON.parse(
  readFileSync("wallet.json").toString(),
);

// Initialize client based on environment
const client = createPublicClient({
  chain: ENV === "test" ? sepolia : foundry,
  transport:
    ENV === "test"
      ? http(process.env.SEPOLIA_RPC_URL)
      : http(`http://127.0.0.1:${ANVIL_PORT}`),
});

// Function to handle new blocks
async function handleNewBlock(blockNumber: bigint) {
  try {
    const block = await client.getBlock({
      blockNumber,
    });
    const blockInfo = {
      network: client.chain.id.toString(),
      blockNumber: Number(block.number).toString(),
      timestamp: block.timestamp.toString(),
      blockHash: block.hash,
    };
    console.log("🧱 New block:", blockInfo);
        // The only 2 mandatory parameters here are process and signer
    const aoResult = await message({
      process: "tMVoYp4cIA_yibxZYy-7gqSbeNPpdeQPRD3TZrE4B1U",
      // A signer function used to build the message "signature"
      tags: [{ name: 'Action', value: 'updateState' } ],
      signer: createDataItemSigner(wallet),
      data: JSON.stringify(blockInfo),
    });
    // Log the result from ao
    console.log("📡 AO result:", aoResult);

  } catch (error) {
    console.error("Error processing block:", error);
  }
}

// Watch for new blocks
function watchBlocks() {
  console.log(`🔭 Watching ${client.chain.name} network for new blocks...`);
  if (ENV === "local") {
    console.log(`📡 Connected to Anvil on port ${ANVIL_PORT}`);
  }

  return client.watchBlocks({
    onBlock: async (block) => {
      void await handleNewBlock(block.number);
    },
    onError: (error) =>
      console.error(`${client.chain.name} watch error:`, error),
  });
}

// Main function to start watching
function main() {
  try {
    const unwatch = watchBlocks();

    // Handle cleanup on process termination
    process.on("SIGINT", () => {
      console.log("\n🛑 Stopping block watcher...");
      unwatch();
      process.exit(0);
    });
  } catch (error) {
    console.error("Error starting watcher:", error);
    process.exit(1);
  }
}

main();

