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
│   │   ├── UserValidatorManual.sol              # Type 1: Manual whitelist
│   │   ├── UserValidator.sol                    # Type 2: ERC-8004 balanceOf check
│   │   └── UserValidatorPreRegistrated.sol      # Type 3: Pre-registration + signature + expiration
│   ├── script/
│   │   ├── DeployUserValidatorManual.s.sol              # Deploy Type 1
│   │   ├── DeployUserValidator.s.sol                    # Deploy Type 2
│   │   └── DeployUserValidatorPreRegistrated.s.sol      # Deploy Type 3
│   ├── Makefile                  # Deploy commands
│   ├── .env.example              # Environment variables template
│   ├── lib/                      # Git submodules (ERC-8004, OpenZeppelin, etc.)
│   └── foundry.toml
└── scripts/
    ├── python/
    │   ├── sign_evvm_authorization.py
    │   ├── requirements.txt
    │   ├── .env.example
    │   └── README.md
    └── ts/
        ├── sign-evvm-authorization.ts
        ├── package.json
        ├── .env.example
        └── README.md
```

## Contracts

There are 3 validator types with increasing complexity and control:

### 1. UserValidatorManual (Simple)

The simplest validator. Admin manually manages a whitelist of allowed addresses.

```solidity
canExecute(user) = allowedUsers[user]
```

**Use case:** When you need full control over who can execute. The admin must explicitly add each user via `setAllowedUser()`.

### 2. UserValidator (Medium)

Validates that the user owns at least one ERC-8004 agent. If they are a registered agent, they can interact.

```solidity
canExecute(user) = identityRegistry.balanceOf(user) > 0
```

Uses the EVVM testnet contracts library (`ProposalStructs`, `IdentityRegistryUpgradeable`).

**Use case:** Open access for any registered ERC-8004 agent. No per-user admin approval needed.

**Limitation:** Cannot identify which specific agentIds the user owns.

### 3. UserValidatorPreRegistrated (Advanced)

Like `UserValidator`, but with atomic and advanced execution controls:

1. Agent must pre-register an agentId with an expiration timestamp
2. Agent must have a valid signature from `evvmAuthorizer` in the ERC-8004 metadata
3. Signature includes `expiresAt` for time-limited authorization

```solidity
keccak256(abi.encodePacked(
    "EVVM_AGENT_AUTH",
    block.chainid,
    address(this),
    address(identityRegistry),
    agentId,
    expiresAt
))
```

**Use case:** When you need to control exactly which agents can execute AND for how long they can execute. The signature with expiration time enables time-limited authorization.

**Key features:**
- Pre-registration proves agent ownership
- Signature authorizes specific agent for specific whitelist
- Expiration time enables time-limited access control

**IMPORTANT:** This validator requires the use of the signing scripts (`scripts/python/` or `scripts/ts/`) to generate the authorization signatures with expiration timestamps that must match exactly with the `expiresAt` value used during `preRegisterAgent()`.

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
  --agent-id 22 \
  --expires-at 1700000000
```

### TypeScript

```bash
cd scripts/ts
npm install

export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."

npm run sign -- \
  --chain-id 1 \
  --whitelist 0xYourValidatorContract \
  --agent-id 22 \
  --expires-at 1700000000
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--chain-id` | Chain ID where the validator is deployed | `1` |
| `--whitelist` | Validator contract address (required) | - |
| `--agent-id` | ERC-8004 agentId to authorize (required) | - |
| `--registry` | ERC-8004 Identity Registry address | `0x8004...` |
| `--private-key` | EVVM authorizer private key | env var |
| `--expires-at` | Expiration timestamp (required, must match preRegisterAgent) | - |

### Authorization Flow

The Type 3 validator uses time-limited authorizations:

1. **Generate signature** with expiration timestamp:
```bash
python sign_evvm_authorization.py \
  --chain-id 1 \
  --whitelist 0xValidator \
  --agent-id 22 \
  --expires-at 1700000000
```

2. **Store signature** in ERC-8004 Identity Registry:
```bash
cast send 0x8004... \
  "setMetadata(uint256,string,bytes)" \
  22 \
  "evvmAuthSignature" \
  0xSignatureHex \
  --private-key <AGENT_OWNER_PRIVATE_KEY>
```

3. **Pre-register agent** with the same expiration:
```bash
cast send 0xValidator \
  "preRegisterAgent(uint256,uint256)" \
  22 \
  1700000000 \
  --from <AGENT_OWNER_ADDRESS>
```

**IMPORTANT:** The `expiresAt` timestamp must match exactly between the signature and `preRegisterAgent()`.

## Onchain Storage

After generating the signature, the agent owner stores it in the official registry:

```bash
# Store signature in ERC-8004 Identity Registry
cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
  "setMetadata(uint256,string,bytes)" \
  22 \
  "evvmAuthSignature" \
  0xSignatureHex \
  --private-key <AGENT_OWNER_PRIVATE_KEY> \
  --rpc-url <ETHEREUM_MAINNET_RPC_URL>

# Pre-register agent with expiration (Type 3 only)
cast send 0xValidatorContract \
  "preRegisterAgent(uint256,uint256)" \
  22 \
  1700000000 \
  --from <AGENT_OWNER_ADDRESS> \
  --private-key <AGENT_OWNER_PRIVATE_KEY> \
  --rpc-url <ETHEREUM_MAINNET_RPC_URL>
```

## Build

```bash
cd contracts
forge build
```

## Deploy

Each validator type has its own deployment script. Use the Makefile or forge directly.

### Using Makefile

```bash
cd contracts

# Set required env vars first
export ADMIN=0xYourAdminAddress
export EVVM_AUTHORIZER=0xAuthorizerAddress  # Type 3 only
export RPC_URL_TESTNET=https://...
export ETHERSCAN_API=your_key

# Deploy Type 1: Manual whitelist
make deployUserValidatorManual

# Deploy Type 2: ERC-8004 balanceOf
make deployUserValidator

# Deploy Type 3: Pre-registration + Signature
make deployUserValidatorPreRegistrated
```

### Using Forge Directly

#### Type 1: UserValidatorManual

```bash
cd contracts

ADMIN=0xYourAdminAddress \
forge script script/DeployUserValidatorManual.s.sol:DeployUserValidatorManual \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

#### Type 2: UserValidator (ERC-8004 balanceOf)

```bash
cd contracts

ADMIN=0xYourAdminAddress \
forge script script/DeployUserValidator.s.sol:DeployUserValidator \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

The script auto-detects the Identity Registry address based on chain ID.

#### Type 3: UserValidatorPreRegistrated (Pre-registration + Signature)

```bash
cd contracts

ADMIN=0xYourAdminAddress \
EVVM_AUTHORIZER=0xAuthorizerAddress \
forge script script/DeployUserValidatorPreRegistrated.s.sol:DeployUserValidatorPreRegistrated \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

**Post-deployment setup for Type 3:**

1. Generate authorization signature:
```bash
cd scripts/python
python sign_evvm_authorization.py \
  --chain-id 1 \
  --whitelist 0xDeployedValidator \
  --agent-id 22 \
  --expires-at 1700000000
```

2. Store signature in ERC-8004 Identity Registry:
```bash
cast send 0x8004... \
  "setMetadata(uint256,string,bytes)" \
  22 \
  "evvmAuthSignature" \
  0xSignatureHex \
  --private-key <AGENT_OWNER_PRIVATE_KEY>
```

3. Pre-register agent with expiration:
```bash
cast send 0xDeployedValidator \
  "preRegisterAgent(uint256,uint256)" \
  22 \
  1700000000 \
  --from <AGENT_OWNER_ADDRESS>
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ADMIN` | All types | Admin address for the validator |
| `EVVM_AUTHORIZER` | Type 3 only | Address that signs agent authorizations |
| `IDENTITY_REGISTRY` | Optional | Override auto-detected registry address (Type 2 & 3) |

**Type 3 post-deployment:**
- `--expires-at`: Unix timestamp when authorization expires (must match in signature and preRegisterAgent)

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
- **Production hardening**: OpenZeppelin ECDSA, admin controls, revocation strategy
- **Additional chain support**: Expand auto-detection for more networks

## Important

A Solidity contract can only directly read contracts on its own chain.

For this demo, if the validator points to the official Ethereum Mainnet registry,
the validator must also be executed in an Ethereum-readable context.

If EVVM is on another chain, use a same-chain official deployment, mirror, oracle,
bridge, state proof mechanism, or equivalent read layer.
