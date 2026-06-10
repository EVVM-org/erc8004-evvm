#!/usr/bin/env python3
"""
sign_evvm_authorization.py

Creates the EVVM authorization signature for the workshop demo.

This signature is intended to be stored as onchain metadata in the official
ERC-8004 Identity Registry.

Metadata convention used by WhitelistEVVM_PreRegisteredERC8004.sol:

    metadataKey   = "evvmAuthSignature"
    metadataValue = <65-byte ECDSA signature>

The signature means:

    "This ERC-8004 agentId is authorized for this exact EVVM whitelist."

The signed digest matches Solidity:

    keccak256(
        abi.encodePacked(
            "EVVM_AGENT_AUTH",
            block.chainid,
            address(whitelist),
            address(identityRegistry),
            agentId
        )
    )

Then it is wrapped using Ethereum Signed Message format, equivalent to:

    keccak256("\\x19Ethereum Signed Message:\\n32" || digest)

Install:

    pip install web3 eth-account

Usage:

    export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."

    python sign_evvm_authorization.py \
        --chain-id 1 \
        --whitelist 0xYourWhitelistEVVMContract \
        --agent-id 22

Optional:

    --registry 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432

Default registry:

    Ethereum Mainnet ERC-8004 Identity Registry:
    0x8004A169FB4a3325136EB29fA0ceB6D2e539a432

After generating the signature, the agent owner or authorized operator must store
it in the official Identity Registry, for example with Foundry cast:

    cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
        "setMetadata(uint256,string,bytes)" \
        <AGENT_ID> \
        "evvmAuthSignature" \
        <SIGNATURE_HEX> \
        --private-key <AGENT_OWNER_PRIVATE_KEY> \
        --rpc-url <ETHEREUM_MAINNET_RPC_URL>

Important:
- The signer in EVVM_AUTHORIZER_PRIVATE_KEY must be the same address configured
  as evvmAuthorizer in WhitelistEVVM_PreRegisteredERC8004.
- The metadata transaction must be sent by whoever has permission to update the
  agent metadata in the ERC-8004 Identity Registry.
"""

import argparse
import os
from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3


DEFAULT_ETHEREUM_MAINNET_IDENTITY_REGISTRY = "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
METADATA_KEY = "evvmAuthSignature"


SET_METADATA_ABI = [
    {
        "type": "function",
        "name": "setMetadata",
        "stateMutability": "nonpayable",
        "inputs": [
            {"name": "agentId", "type": "uint256"},
            {"name": "metadataKey", "type": "string"},
            {"name": "metadataValue", "type": "bytes"},
        ],
        "outputs": [],
    }
]


def normalize_address(value: str, name: str) -> str:
    if not Web3.is_address(value):
        raise SystemExit(f"Invalid {name}: {value}")
    return Web3.to_checksum_address(value)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sign EVVM authorization for an ERC-8004 agentId."
    )
    parser.add_argument(
        "--chain-id",
        type=int,
        default=1,
        help="Chain ID where the whitelist contract is deployed. Default: 1.",
    )
    parser.add_argument(
        "--whitelist",
        required=True,
        help="WhitelistEVVM_PreRegisteredERC8004 contract address.",
    )
    parser.add_argument(
        "--agent-id",
        type=int,
        required=True,
        help="ERC-8004 agentId to authorize.",
    )
    parser.add_argument(
        "--registry",
        default=DEFAULT_ETHEREUM_MAINNET_IDENTITY_REGISTRY,
        help="ERC-8004 Identity Registry address. Default: Ethereum Mainnet official registry.",
    )
    parser.add_argument(
        "--private-key",
        default=os.environ.get("EVVM_AUTHORIZER_PRIVATE_KEY"),
        help="EVVM authorizer private key. Prefer EVVM_AUTHORIZER_PRIVATE_KEY env var.",
    )

    args = parser.parse_args()

    if not args.private_key:
        raise SystemExit(
            "Missing private key. Set EVVM_AUTHORIZER_PRIVATE_KEY or pass --private-key."
        )

    whitelist = normalize_address(args.whitelist, "whitelist address")
    registry = normalize_address(args.registry, "registry address")

    authorizer = Account.from_key(args.private_key)

    # Must match Solidity authorizationDigest(agentId):
    #
    # keccak256(
    #   abi.encodePacked(
    #     "EVVM_AGENT_AUTH",
    #     block.chainid,
    #     address(this),
    #     address(identityRegistry),
    #     agentId
    #   )
    # )
    digest = Web3.solidity_keccak(
        ["string", "uint256", "address", "address", "uint256"],
        ["EVVM_AGENT_AUTH", args.chain_id, whitelist, registry, args.agent_id],
    )

    # Must match Solidity:
    # keccak256("\x19Ethereum Signed Message:\n32" || digest)
    message = encode_defunct(primitive=digest)
    signed = Account.sign_message(message, args.private_key)
    signature_hex = Web3.to_hex(signed.signature)

    recovered = Account.recover_message(message, signature=signed.signature)

    # Prepare calldata for setMetadata(agentId, "evvmAuthSignature", signature)
    contract = Web3().eth.contract(address=registry, abi=SET_METADATA_ABI)

    try:
        set_metadata_calldata = contract.functions.setMetadata(
            args.agent_id,
            METADATA_KEY,
            bytes.fromhex(signature_hex[2:]),
        )._encode_transaction_data()
    except Exception:
        set_metadata_calldata = None

    print("=== EVVM ERC-8004 Agent Authorization ===")
    print()
    print(f"EVVM authorizer address: {authorizer.address}")
    print(f"Recovered signer:        {recovered}")
    print(f"Chain ID:                {args.chain_id}")
    print(f"Whitelist contract:      {whitelist}")
    print(f"Identity Registry:       {registry}")
    print(f"Agent ID:                {args.agent_id}")
    print()
    print("Metadata key:")
    print(METADATA_KEY)
    print()
    print("Metadata value / signature:")
    print(signature_hex)
    print()
    print("Digest signed:")
    print(Web3.to_hex(digest))
    print()

    if set_metadata_calldata:
        print("Calldata for setMetadata(agentId, metadataKey, metadataValue):")
        print(set_metadata_calldata)
        print()

    print("Foundry cast example:")
    print(
        "cast send "
        f"{registry} "
        '"setMetadata(uint256,string,bytes)" '
        f"{args.agent_id} "
        f'"{METADATA_KEY}" '
        f"{signature_hex} "
        "--private-key <AGENT_OWNER_PRIVATE_KEY> "
        "--rpc-url <ETHEREUM_MAINNET_RPC_URL>"
    )


if __name__ == "__main__":
    main()
