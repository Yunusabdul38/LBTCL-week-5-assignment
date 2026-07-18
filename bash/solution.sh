# Get blockchain info using bitcoin-cli
blockchain_info=$(bitcoin-cli -regtest getblockchaininfo)

# Print the blockchain info
echo "$blockchain_info"

# Create two wallets called Miner and Alice
if ! bitcoin-cli -regtest listwallets | jq -e '.[] | select(. == "Miner")' >/dev/null; then
    bitcoin-cli -regtest loadwallet "Miner" || bitcoin-cli -regtest createwallet "Miner"
fi
if ! bitcoin-cli -regtest listwallets | jq -e '.[] | select(. == "Alice")' >/dev/null; then
    bitcoin-cli -regtest loadwallet "Alice" || bitcoin-cli -regtest createwallet "Alice"
fi

# Fund the Miner wallet
miner_address=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress)
bitcoin-cli -regtest generatetoaddress 101 "$miner_address"  >/dev/null

# Send some coins to Alice's wallet
alice_address=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress)
txid_fund=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$alice_address" 20)
bitcoin-cli -regtest generatetoaddress 1 "$miner_address"
alice_balance=$(bitcoin-cli -regtest -rpcwallet=Alice getbalance)
is_positive=$(jq -n "$alice_balance > 0")
if [ "$is_positive" != "true" ]; then
    exit 1
fi

# Create refund transaction where Alice pays 10 BTC to Miner
# Additionally, add a relative timelock of 10 blocks
miner_refund_address=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress)
alice_change_address=$(bitcoin-cli -regtest -rpcwallet=Alice getrawchangeaddress)
alice_utxos=$(bitcoin-cli -regtest -rpcwallet=Alice listunspent)
alice_utxo=$(echo "$alice_utxos" | jq -e --arg txid "$txid_fund" '.[] | select(.txid == $txid)')
alice_txid=$(echo "$alice_utxo" | jq -r '.txid')
alice_vout=$(echo "$alice_utxo" | jq -r '.vout')
alice_amount=$(echo "$alice_utxo" | jq -r '.amount')
change_amount=$(jq -n "$alice_amount - 10 - 0.0001")
raw_tx=$(bitcoin-cli -regtest createrawtransaction "[{\"txid\":\"$alice_txid\",\"vout\":$alice_vout,\"sequence\":10}]" "[{\"$miner_refund_address\":10},{\"$alice_change_address\":$change_amount}]")

# Sign and broadcast the transaction. Is the broadcast successful?
signed_tx_json=$(bitcoin-cli -regtest -rpcwallet=Alice signrawtransactionwithwallet "$raw_tx")
signed_tx=$(echo "$signed_tx_json" | jq -r '.hex')
bitcoin-cli -regtest sendrawtransaction "$signed_tx" 2>&1 || true

# Generate 10 blocks
bitcoin-cli -regtest generatetoaddress 10 "$miner_address"  >/dev/null

# Broadcast the transaction again. Is the broadcast successful now?
bitcoin-cli -regtest sendrawtransaction "$signed_tx" || true
txid_refund=$(bitcoin-cli -regtest decoderawtransaction "$signed_tx" | jq -r '.txid')
bitcoin-cli -regtest generatetoaddress 1 "$miner_address"
bitcoin-cli -regtest -rpcwallet=Alice getbalance

# Output the transaction ID to `out.txt`
echo "$txid_refund" > out.txt