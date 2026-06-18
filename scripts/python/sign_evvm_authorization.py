#!/usr/bin/env python3
"""
Creates the EVVM authorization signature for an ERC-8004 agent.

This script generates an ECDSA signature that authorizes an ERC-8004 agent
to execute through the EVVM whitelist system. The signature is stored as
onchain metadata in the official ERC-8004 Identity Registry.

## Metadata Convention

Used by ``UserValidatorPreRegistrated.sol``::

    metadataKey   = "evvmAuthSignature"
    metadataValue = <65-byte ECDSA signature>

## Signature Semantics

The signature attests:

    "This ERC-8004 agentId is authorized for this exact EVVM whitelist,
     until this expiration time."

## Digest Construction

The signed digest matches the Solidity implementation::

    keccak256(
        abi.encodePacked(
            "EVVM_AGENT_AUTH",
            block.chainid,
            address(whitelist),
            address(identityRegistry),
            agentId,
            expiresAt
        )
    )

The resulting 32-byte digest is converted to a 66-character hex string
(with ``0x`` prefix) and signed using the Ethereum Signed Message format::

    keccak256("\\x19Ethereum Signed Message:\\n66" || hexString)

IMPORTANT: The expiresAt timestamp in the signature MUST match the expiresAt
value used during preRegisterAgent().

## Installation

.. code-block:: bash

    pip install -r requirements.txt

## Usage

.. code-block:: bash

    export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."

    python sign_evvm_authorization.py \\\\
        --chain-id 1 \\\\
        --whitelist 0xYourWhitelistEVVMContract \\\\
        --agent-id 22 \\\\
        --expires-at 1700000000

### Options

=================  =================================================  ===========
Option             Description                                        Default
=================  =================================================  ===========
--chain-id         Chain ID where the whitelist is deployed           1
--whitelist        Whitelist contract address (required)              -
--agent-id         ERC-8004 agentId to authorize (required)           -
--registry         ERC-8004 Identity Registry address                 0x8004...
--expires-at       Expiration timestamp (required)                    -
--private-key      EVVM authorizer private key                        env var
=================  =================================================  ===========

## Onchain Storage

After generating the signature, store it in the ERC-8004 Identity Registry::

    cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \\\\
        "setMetadata(uint256,string,bytes)" \\\\
        <AGENT_ID> \\\\
        "evvmAuthSignature" \\\\
        <SIGNATURE_HEX> \\\\
        --private-key <AGENT_OWNER_PRIVATE_KEY> \\\\
        --rpc-url <ETHEREUM_MAINNET_RPC_URL>

## Important Notes

- The signer in ``EVVM_AUTHORIZER_PRIVATE_KEY`` must match the ``evvmAuthorizer``
  configured in ``UserValidatorPreRegistrated``.
- The metadata transaction must be sent by whoever has permission to update
  the agent metadata in the ERC-8004 Identity Registry.
- The expiresAt timestamp must match exactly between the signature and preRegisterAgent().
"""

import argparse
import os
from typing import Optional, Tuple

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
    """
    Validate and checksum an Ethereum address.

    Args:
        value: The address string to validate.
        name: Human-readable name for error messages.

    Returns:
        Checksummed Ethereum address.

    Raises:
        SystemExit: If the address is invalid.
    """
    if not Web3.is_address(value):
        raise SystemExit(f"Invalid {name}: {value}")
    return Web3.to_checksum_address(value)


def compute_authorization_digest(
    chain_id: int,
    whitelist: str,
    registry: str,
    agent_id: int,
    expires_at: int,
) -> bytes:
    """
    Compute the authorization digest matching Solidity's canExecute() digest.

    The digest is computed as::

        keccak256(
            abi.encodePacked(
                "EVVM_AGENT_AUTH",
                chainId,
                whitelist,
                registry,
                agentId,
                expiresAt
            )
        )

    Args:
        chain_id: Chain ID where the whitelist contract is deployed.
        whitelist: Address of the whitelist contract.
        registry: Address of the ERC-8004 Identity Registry.
        agent_id: The ERC-8004 agent identifier.
        expires_at: Unix timestamp when the authorization expires.

    Returns:
        32-byte digest as bytes.
    """
    return Web3.solidity_keccak(
        ["string", "uint256", "address", "address", "uint256", "uint256"],
        ["EVVM_AGENT_AUTH", chain_id, whitelist, registry, agent_id, expires_at],
    )


def bytes32_to_hex_string(digest: bytes) -> str:
    """
    Convert a 32-byte digest to a 66-character hex string with 0x prefix.

    This matches the Solidity ``AdvancedStrings.bytes32ToString()`` function.

    Args:
        digest: 32-byte value to convert.

    Returns:
        Hex string in format "0x..." (66 characters total).
    """
    return "0x" + digest.hex()


def sign_authorization(
    private_key: str,
    digest_hex: str,
) -> Tuple[str, str]:
    """
    Sign the authorization message using EIP-191.

    The signature is produced over the hex string representation of the
    digest, matching Solidity's ``SignatureRecover.recoverSigner()``::

        keccak256("\\x19Ethereum Signed Message:\\n66" || digest_hex)

    Args:
        private_key: Private key of the EVVM authorizer.
        digest_hex: 66-character hex string of the authorization digest.

    Returns:
        Tuple of (signature_hex, recovered_address).
    """
    message = encode_defunct(text=digest_hex)
    signed = Account.sign_message(message, private_key)
    signature_hex = Web3.to_hex(signed.signature)
    recovered = Account.recover_message(message, signature=signed.signature)
    return signature_hex, recovered


def encode_set_metadata_calldata(
    registry: str,
    agent_id: int,
    signature_hex: str,
) -> Optional[str]:
    """
    Encode the calldata for setMetadata() on the Identity Registry.

    Args:
        registry: Address of the ERC-8004 Identity Registry.
        agent_id: The ERC-8004 agent identifier.
        signature_hex: Hex-encoded signature (with 0x prefix).

    Returns:
        Hex-encoded calldata string, or None if encoding fails.
    """
    contract = Web3().eth.contract(address=registry, abi=SET_METADATA_ABI)
    try:
        return contract.functions.setMetadata(
            agent_id,
            METADATA_KEY,
            bytes.fromhex(signature_hex[2:]),
        )._encode_transaction_data()
    except Exception:
        return None


def print_authorization_output(
    authorizer_address: str,
    recovered_address: str,
    chain_id: int,
    whitelist: str,
    registry: str,
    agent_id: int,
    expires_at: int,
    signature_hex: str,
    digest: bytes,
    digest_hex: str,
    calldata: Optional[str],
) -> None:
    """
    Print the authorization result in a human-readable format.

    Args:
        authorizer_address: Address of the EVVM authorizer.
        recovered_address: Address recovered from the signature.
        chain_id: Chain ID where the whitelist is deployed.
        whitelist: Address of the whitelist contract.
        registry: Address of the ERC-8004 Identity Registry.
        agent_id: The ERC-8004 agent identifier.
        expires_at: Unix timestamp when the authorization expires.
        signature_hex: Hex-encoded signature.
        digest: Original 32-byte digest.
        digest_hex: Hex string representation of the digest.
        calldata: Encoded calldata for setMetadata(), if available.
    """
    from datetime import datetime

    print("=== EVVM ERC-8004 Agent Authorization ===")
    print()
    print(f"EVVM authorizer address: {authorizer_address}")
    print(f"Recovered signer:        {recovered_address}")
    print(f"Chain ID:                {chain_id}")
    print(f"Whitelist contract:      {whitelist}")
    print(f"Identity Registry:       {registry}")
    print(f"Agent ID:                {agent_id}")
    print(f"Expires at:              {expires_at} ({datetime.fromtimestamp(expires_at)})")
    print()
    print("Metadata key:")
    print(METADATA_KEY)
    print()
    print("Metadata value / signature:")
    print(signature_hex)
    print()
    print("Digest (bytes32):")
    print(Web3.to_hex(digest))
    print()
    print("Message signed (hex string, 66 chars):")
    print(digest_hex)
    print()

    if calldata:
        print("Calldata for setMetadata(agentId, metadataKey, metadataValue):")
        print(calldata)
        print()

    print("Foundry cast example:")
    print(
        "cast send "
        f"{registry} "
        '"setMetadata(uint256,string,bytes)" '
        f"{agent_id} "
        f'"{METADATA_KEY}" '
        f"{signature_hex} "
        "--private-key <AGENT_OWNER_PRIVATE_KEY> "
        "--rpc-url <ETHEREUM_MAINNET_RPC_URL>"
    )
    print()
    print("Pre-registration example:")
    print(
        "cast send "
        f"{whitelist} "
        '"preRegisterAgent(uint256,uint256)" '
        f"{agent_id} "
        f"{expires_at} "
        "--from <AGENT_OWNER_ADDRESS> "
        "--private-key <AGENT_OWNER_PRIVATE_KEY> "
        "--rpc-url <RPC_URL>"
    )


def parse_arguments() -> argparse.Namespace:
    """
    Parse command-line arguments.

    Returns:
        Parsed argument namespace with the following attributes:
            - chain_id: Chain ID (default: 1)
            - whitelist: Whitelist contract address (required)
            - agent_id: ERC-8004 agent identifier (required)
            - registry: Identity Registry address (default: mainnet)
            - expires_at: Expiration timestamp (required)
            - private_key: Authorizer private key (from arg or env)
    """
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
        help="UserValidatorPreRegistrated contract address.",
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
        "--expires-at",
        type=int,
        required=True,
        help="Unix timestamp when the authorization expires (must match preRegisterAgent).",
    )
    parser.add_argument(
        "--private-key",
        default=os.environ.get("EVVM_AUTHORIZER_PRIVATE_KEY"),
        help="EVVM authorizer private key. Prefer EVVM_AUTHORIZER_PRIVATE_KEY env var.",
    )
    return parser.parse_args()


def main() -> None:
    """
    Main entry point for the authorization signing script.

    Orchestrates the complete flow:
        1. Parse and validate CLI arguments
        2. Compute the authorization digest (with expiresAt)
        3. Convert digest to hex string
        4. Sign the hex string using EIP-191
        5. Output results and usage examples
    """
    args = parse_arguments()

    if not args.private_key:
        raise SystemExit(
            "Missing private key. Set EVVM_AUTHORIZER_PRIVATE_KEY or pass --private-key."
        )

    whitelist = normalize_address(args.whitelist, "whitelist address")
    registry = normalize_address(args.registry, "registry address")

    authorizer = Account.from_key(args.private_key)

    digest = compute_authorization_digest(
        args.chain_id, whitelist, registry, args.agent_id, args.expires_at
    )

    digest_hex = bytes32_to_hex_string(digest)

    signature_hex, recovered = sign_authorization(args.private_key, digest_hex)

    calldata = encode_set_metadata_calldata(registry, args.agent_id, signature_hex)

    print_authorization_output(
        authorizer_address=authorizer.address,
        recovered_address=recovered,
        chain_id=args.chain_id,
        whitelist=whitelist,
        registry=registry,
        agent_id=args.agent_id,
        expires_at=args.expires_at,
        signature_hex=signature_hex,
        digest=digest,
        digest_hex=digest_hex,
        calldata=calldata,
    )


if __name__ == "__main__":
    main()
