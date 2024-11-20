
# HOW TO RUN

## TEMPLATE ENV

```env
export BONSAI_API_KEY="YOUR_API_KEY" # see form linked in the previous section
export BONSAI_API_URL="https://api.bonsai.xyz" # provided with your api key

export ETH_RPC_URL="http://localhost:8545"  # EXAMPLE FOR LOCAL DEMO
export RUST_LOG=info

```

## RUN COMMAND

```bash
source .env && cargo run --bin publisher -- \
    --eth-rpc-url=$ETH_RPC_URL \
    --counter-address=$COUNTER_ADDRESS \
    --token-contract=$TOYKEN_ADDRESS \
    --port=3000
```


## ENDPOINT USE
```bash
 curl http://localhost:3000/generate/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
``` 