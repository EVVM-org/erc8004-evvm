# EVVM + ERC-8004 Official Registry Whitelist Examples

> **Status: Proof of Concept**
>
> This repository is a proof of concept (PoC). It is
> not production-ready. Automated tests are not yet implemented, and several
> processes (signature verification, pre-registration flows, deployment scripts)
> are subject to refinement. Use at your own risk.

EVVM user validators using the official ERC-8004 Identity Registry.

These examples do **not** deploy a custom ERC-8004 registry.

They use the official Ethereum Mainnet ERC-8004 Identity Registry by default:

`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`

## Project Structure

```
erc8004-evvm/
├── contracts/                    # Foundry project
│   ├── src/
│   │   ├── UserValidatorBasic.sol               # Type 1: Manual whitelist (UserValidatorManual)
│   │   ├── UserValidator.sol                    # Type 2: ERC-8004 balanceOf check
│   │   ├── UserValidatorPreRegistrated.sol      # Type 3: Pre-registration + signature
│   │   ├── WhitelistEVVM_BasicERC8004.sol       # Standalone reference (no external deps)
│   │   └── WhitelistEVVM_PreRegisteredERC8004.sol
│   ├── script/
│   │   └── DeployValidator.s.sol                # Deployment script (flag-based)
│   ├── lib/                      # Git submodules (ERC-8004, OpenZeppelin, etc.)
│   └── foundry.toml
└── scripts/
    ├── python/
    │   ├── sign_evvm_authorization.py
    │   ├── requirements.txt
    │   └── README.md
    └── ts/
        ├── sign-evvm-authorization.ts
        ├── package.json
        └── README.md
```

## Contracts

### 1. UserValidator.sol

Basic EVVM validator using `balanceOf()`:

```solidity
canExecute(user) = identityRegistry.balanceOf(user) > 0
```

Uses the EVVM testnet contracts library (`ProposalStructs`, `IdentityRegistryUpgradeable`).

This proves that with only an address, an EVVM validator can know whether the
address owns one or more registered ERC-8004 agents.

Limitation:

- It cannot list agentIds from only an address in the ERC-721 base interface.

### 2. UserValidatorPreRegistrated.sol

Pre-registration + signature authorization:

1. Agent calls `preRegisterAgent(agentId)`.
2. Contract checks that caller is `ownerOf(agentId)` or `getAgentWallet(agentId)`.
3. EVVM calls `canExecute(user)`.
4. Contract verifies:
   - User has an active pre-registration
   - User is still the current owner or verified agentWallet
   - Agent has metadata key `evvmAuthSignature` in the ERC-8004 registry
   - Metadata is a valid 65-byte ECDSA signature
   - Signature recovers to the configured `evvmAuthorizer`

The signature digest (matching the signing scripts):

```solidity
keccak256(abi.encodePacked(
    "EVVM_AGENT_AUTH",
    block.chainid,
    address(this),
    address(identityRegistry),
    agentId
))
```

Converted to a 66-character hex string and signed using Ethereum Signed Message format.

### 3. Standalone Reference Versions

`WhitelistEVVM_BasicERC8004.sol` and `WhitelistEVVM_PreRegisteredERC8004.sol` are
self-contained reference implementations with no external dependencies beyond minimal
inline interfaces. They serve as documentation and can be deployed independently.

## Signing Scripts

Generate the EVVM authorizer signature to store in ERC-8004 metadata:

```text
metadataKey   = evvmAuthSignature
metadataValue = 65-byte ECDSA signature
```

### Python

```bash
cd scripts/python
pip install -r requirements.txt

export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."

python sign_evvm_authorization.py \
  --chain-id 1 \
  --whitelist 0xYourValidatorContract \
  --agent-id 22
```

### TypeScript

```bash
cd scripts/ts
npm install

export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."

npm run sign -- \
  --chain-id 1 \
  --whitelist 0xYourValidatorContract \
  --agent-id 22
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--chain-id` | Chain ID where the validator is deployed | `1` |
| `--whitelist` | Validator contract address (required) | - |
| `--agent-id` | ERC-8004 agentId to authorize (required) | - |
| `--registry` | ERC-8004 Identity Registry address | `0x8004...` |
| `--private-key` | EVVM authorizer private key | env var |

## Onchain Storage

After generating the signature, the agent owner stores it in the official registry:

```bash
cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
  "setMetadata(uint256,string,bytes)" \
  22 \
  "evvmAuthSignature" \
  0xSignatureHex \
  --private-key <AGENT_OWNER_PRIVATE_KEY> \
  --rpc-url <ETHEREUM_MAINNET_RPC_URL>
```

## Build

```bash
cd contracts
forge build
```

## Deploy

Deploy validators using the `DeployValidator` script with environment variables:

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `VALIDATOR_TYPE` | Yes | `1` (manual), `2` (balanceOf), or `3` (pre-registered) |
| `ADMIN` | Yes | Admin address for the validator |
| `EVVM_AUTHORIZER` | Type 3 only | Address that signs agent authorizations |
| `IDENTITY_REGISTRY` | Optional | Override auto-detected registry address |

### Type 1: UserValidatorManual (Manual Whitelist)

```bash
cd contracts

VALIDATOR_TYPE=1 \
ADMIN=0xYourAdminAddress \
forge script script/DeployValidator.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Type 2: UserValidator (ERC-8004 balanceOf)

```bash
cd contracts

VALIDATOR_TYPE=2 \
ADMIN=0xYourAdminAddress \
forge script script/DeployValidator.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

The script auto-detects the Identity Registry address based on chain ID.

### Type 3: UserValidatorPreRegistrated (Pre-registration + Signature)

```bash
cd contracts

VALIDATOR_TYPE=3 \
ADMIN=0xYourAdminAddress \
EVVM_AUTHORIZER=0xAuthorizerAddress \
forge script script/DeployValidator.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Supported Chains

The script auto-detects the Identity Registry for these chains:

**Mainnets** (all use `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`):
Ethereum, Optimism, BSC, Gnosis, Polygon, XLayer, Abstract, Base, Taiko, Arbitrum, Celo, Avalanche, Mantle, Metis, Scroll, Linea

**Testnets** (all use `0x8004A818BFB912233c491871b3d84c89A494BD9e`):
BSC Testnet, Hedera Testnet, Celo Alfajores, Soneium Minato, Sepolia, Optimism Sepolia, Polygon Amoy, Base Sepolia, Arbitrum Sepolia, Avalanche Fuji, Linea Sepolia, Mantle Sepolia, Metis Sepolia, Scroll Sepolia

For unsupported chains, set `IDENTITY_REGISTRY` env var to override.

## Work in Progress

The following areas are planned but not yet implemented:

- **Automated tests**: Foundry tests for all validator contracts
- **Signature verification tests**: Cross-validation between Solidity and signing scripts
- **Pre-registration flow tests**: End-to-end testing of the full authorization flow
- **Deployment tests**: Script testing on local/testnet environments
- **Production hardening**: OpenZeppelin ECDSA, admin controls, revocation strategy, expiry/deadline
- **Additional chain support**: Expand auto-detection for more networks

## Important

A Solidity contract can only directly read contracts on its own chain.

For this demo, if the validator points to the official Ethereum Mainnet registry,
the validator must also be executed in an Ethereum-readable context.

If EVVM is on another chain, use a same-chain official deployment, mirror, oracle,
bridge, state proof mechanism, or equivalent read layer.
