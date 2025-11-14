#!/usr/bin/env python3
"""
Update contract bytecode on Tenderly fork using tenderly_setCode RPC method.
This allows replacing old contract code with new implementations on the fork.

For contracts with immutables, we deploy a temporary instance with the correct
constructor args, then extract and use its deployed bytecode (which has the
immutables properly embedded).

Usage:
    python3 script/utils/update_tenderly_contract.py YToken
    python3 script/utils/update_tenderly_contract.py Operator
"""

import json
import os
import sys
import subprocess
from web3 import Web3
from eth_account import Account
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

TENDERLY_RPC_URL = os.getenv("TENDERLY_URL")
if not TENDERLY_RPC_URL:
    raise ValueError("TENDERLY_URL not found in .env file")

# Contract configurations
CONTRACTS = {
    "YToken": {
        "target_address": "0x22222222aEA0076fCA927a3f44dc0B4FdF9479D6",
        "artifact_path": "out/YToken.sol/YToken.json",
        "constructor_args": [
            "0x0000000C90799449af8eE0B240Da639144a36C6A",  # locker
            "0x01791F726B4103694969820be083196cC7c045fF",  # token (YB)
            "Yearn Boosted YB",                            # name
            "yYB"                                          # symbol
        ]
    },
    "Operator": {
        "target_address": "0x1111111Ecd5Ae05422aeCe517072ec33Dbf34af9",
        "artifact_path": "out/Operator.sol/Operator.json",
        "constructor_args": [
            "0x0000000C90799449af8eE0B240Da639144a36C6A",  # locker
            "0x1Be14811A3a06F6aF4fA64310a636e1Df04c1c21",  # gaugeController
            "0x2be6670DE1cCEC715bDBBa2e3A6C1A05E496ec78",  # daoVoting
            "0x22222222aEA0076fCA927a3f44dc0B4FdF9479D6",  # yToken
        ]
    }
}

def compile_contracts():
    """Compile all contracts."""
    print("Compiling contracts...")
    result = subprocess.run(
        ["forge", "build", "--silent"],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        raise Exception(f"Compilation failed: {result.stderr}")

    print("✓ Compilation complete")

def get_contract_artifact(artifact_path):
    """Load contract artifact from build output."""
    with open(artifact_path, 'r') as f:
        artifact = json.load(f)
    return artifact

def deploy_temp_contract(w3, contract_name, artifact, constructor_args):
    """Deploy a temporary contract instance to get properly initialized bytecode."""
    print(f"Deploying temporary {contract_name} instance...")

    # Create a funded account for deployment
    temp_account = Account.create()

    # Fund the account using Tenderly's setBalance
    w3.provider.make_request(
        "tenderly_setBalance",
        [temp_account.address, "0x56BC75E2D63100000"]  # 100 ETH
    )

    # Get contract creation bytecode and ABI
    creation_bytecode = artifact["bytecode"]["object"]
    if not creation_bytecode.startswith("0x"):
        creation_bytecode = "0x" + creation_bytecode

    abi = artifact["abi"]

    # Create contract instance
    contract = w3.eth.contract(abi=abi, bytecode=creation_bytecode)

    # Build constructor transaction with dynamic args
    constructor_txn = contract.constructor(*constructor_args).build_transaction({
        'from': temp_account.address,
        'nonce': w3.eth.get_transaction_count(temp_account.address),
        'gas': 3000000,
        'gasPrice': w3.eth.gas_price,
    })

    # Sign and send transaction
    signed_txn = temp_account.sign_transaction(constructor_txn)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)

    print(f"Deployment tx: {tx_hash.hex()}")

    # Wait for receipt
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

    if receipt['status'] != 1:
        raise Exception("Deployment failed")

    deployed_address = receipt['contractAddress']
    print(f"Temporary contract deployed at: {deployed_address}")

    # Get the deployed bytecode (with immutables properly set)
    deployed_bytecode = w3.eth.get_code(deployed_address)

    print(f"Deployed bytecode length: {len(deployed_bytecode)} bytes")

    # Convert to hex string with 0x prefix
    bytecode_hex = deployed_bytecode.hex()
    if not bytecode_hex.startswith("0x"):
        bytecode_hex = "0x" + bytecode_hex

    return bytecode_hex

def update_contract_code(w3, address, bytecode):
    """Update contract code using tenderly_setCode RPC method."""
    print(f"Updating contract at {address}...")

    # Tenderly's custom RPC method to replace bytecode
    result = w3.provider.make_request(
        "tenderly_setCode",
        [address, bytecode]
    )

    if "error" in result:
        raise Exception(f"RPC error: {result['error']}")

    print(f"✓ Contract code updated successfully")
    return result

def verify_update(w3, address):
    """Verify the contract was updated by checking code."""
    code = w3.eth.get_code(address)
    print(f"✓ Contract code length: {len(code)} bytes")
    return code

def main():
    # Parse command line arguments
    if len(sys.argv) < 2:
        print("Usage: python3 script/utils/update_tenderly_contract.py <ContractName>")
        print(f"Available contracts: {', '.join(CONTRACTS.keys())}")
        sys.exit(1)

    contract_name = sys.argv[1]

    if contract_name not in CONTRACTS:
        print(f"Error: Unknown contract '{contract_name}'")
        print(f"Available contracts: {', '.join(CONTRACTS.keys())}")
        sys.exit(1)

    config = CONTRACTS[contract_name]

    # Initialize Web3
    w3 = Web3(Web3.HTTPProvider(TENDERLY_RPC_URL))

    if not w3.is_connected():
        raise Exception("Failed to connect to Tenderly RPC")

    print(f"Connected to Tenderly fork")
    print(f"Network ID: {w3.eth.chain_id}")
    print()

    # Compile contracts
    compile_contracts()

    # Get contract artifact
    artifact = get_contract_artifact(config["artifact_path"])

    # Deploy temporary instance with correct constructor args
    bytecode = deploy_temp_contract(
        w3,
        contract_name,
        artifact,
        config["constructor_args"]
    )

    print()

    # Update the target contract with the properly initialized bytecode
    update_contract_code(w3, config["target_address"], bytecode)

    # Verify
    verify_update(w3, config["target_address"])

    print()
    print("=" * 60)
    print(f"{contract_name} update complete!")
    print(f"Address: {config['target_address']}")
    print("You can now run your tests against the updated contract.")
    print("=" * 60)

if __name__ == "__main__":
    main()
