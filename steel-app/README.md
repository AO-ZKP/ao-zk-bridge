
# HOW TO RUN

## TEMPLATE ENV

```env
# FOR DEPLOYMENT
export ETH_WALLET_PRIVATE_KEY="YOUR_ETH_PRIV_KEY"
export ETH_WALLET_ADDRESS="ETH_ADDRESS" 

export BONSAI_API_KEY="YOUR_API_KEY" # see form linked in the previous section
export BONSAI_API_URL="https://api.bonsai.xyz" # provided with your api key

# EXAMPLE FOR LOCAL DEMO
export ETH_RPC_URL="http://localhost:8545"
export CHAIN_ID=31337

export RUST_LOG=info
export PORT=3000


```

## INITIALISE SUBMODULES

```bash
git submodule init && git submodule update --recursive
```
## BUILD PROJECT
```bash
cargo build
```

## DEPLOY CONTRACT

```bash
./deploy-contract.sh
```

## RUN SERVER

```bash
./start-server.sh
```

## ENDPOINT USE

### CHECK SERVER HEALTH

```bash
curl http://localhost:3000/
```

### GENERATE PROOF OF TRANSACTION (provide wallet address)

```bash
 curl http://localhost:3000/generate/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```
