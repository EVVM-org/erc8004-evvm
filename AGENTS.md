# AGENTS.md - EVVM Authorization Signing Scripts

This document provides guidance for AI agents integrating with the EVVM authorization signing scripts.

## ERC-8004 Context

This project builds on [ERC-8004: Trustless Agents](https://eips.ethereum.org/EIPS/eip-8004), a standard for discovering, choosing, and interacting with agents across organizational boundaries.

### Key ERC-8004 Concepts

**Identity Registry** (ERC-721 with URIStorage):
- Each agent is an NFT with a unique `agentId` (tokenId)
- `ownerOf(agentId)` returns the agent owner
- `balanceOf(address)` returns how many agents an address owns
- `getAgentWallet(agentId)` returns the verified wallet address
- `getMetadata(agentId, key)` / `setMetadata(agentId, key, value)` for on-chain metadata
- When an agent is transferred, `agentWallet` is automatically cleared

**Agent Identity**: An agent is globally identified by:
- `agentRegistry`: `{namespace}:{chainId}:{identityRegistry}` (e.g., `eip155:1:0x8004...`)
- `agentId`: The ERC-721 tokenId

**Metadata System**: The registry supports arbitrary key-value metadata:
```solidity
function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory)
function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external
```

Our project uses the metadata key `"evvmAuthSignature"` to store authorization signatures.

### ERC-8004 Registries

The standard defines three registries:
1. **Identity Registry** - Agent registration (ERC-721 NFTs)
2. **Reputation Registry** - Feedback and scoring
3. **Validation Registry** - Work verification hooks

Our validators interact with the **Identity Registry** to verify agent ownership and read authorization metadata.

## Overview

The signing scripts generate ECDSA signatures that authorize ERC-8004 agents to execute through EVVM whitelists. These signatures are stored as onchain metadata and verified by the `UserValidatorPreRegistrated` contract.

## Script Locations

- **Python**: `scripts/python/sign_evvm_authorization.py`
- **TypeScript**: `scripts/ts/sign-evvm-authorization.ts`

## Core Concept

The scripts implement a time-limited authorization system where:

1. An **authorizer** (backend service) signs a digest containing agent details and expiration time
2. The signature is stored in the ERC-8004 Identity Registry as metadata
3. The agent pre-registers with the same expiration time
4. The validator contract verifies the signature and checks expiration

## Digest Structure

Both scripts generate signatures over this exact digest:

```solidity
keccak256(abi.encodePacked(
    "EVVM_AGENT_AUTH",
    block.chainid,
    address(whitelist),
    address(identityRegistry),
    agentId,
    expiresAt
))
```

**Parameters:**
- `block.chainid`: Chain ID where the validator is deployed
- `whitelist`: Address of the `UserValidatorPreRegistrated` contract
- `identityRegistry`: Address of the ERC-8004 Identity Registry
- `agentId`: The ERC-8004 agent identifier (uint256)
- `expiresAt`: Unix timestamp when authorization expires (uint256)

## Script Interface

### Python Script

```bash
python sign_evvm_authorization.py \
  --chain-id <chain_id> \
  --whitelist <validator_address> \
  --agent-id <agent_id> \
  --expires-at <unix_timestamp> \
  --registry <identity_registry_address> \
  --private-key <authorizer_private_key>
```

**Environment Variables:**
- `EVVM_AUTHORIZER_PRIVATE_KEY`: Private key of the authorizer (alternative to `--private-key`)

**Output:**
- Signature (65 bytes, hex-encoded with 0x prefix)
- Digest (32 bytes, hex-encoded)
- Calldata for `setMetadata()` call
- Example `cast` commands for deployment

### TypeScript Script

```bash
npm run sign -- \
  --chain-id <chain_id> \
  --whitelist <validator_address> \
  --agent-id <agent_id> \
  --expires-at <unix_timestamp> \
  --registry <identity_registry_address> \
  --private-key <authorizer_private_key>
```

**Environment Variables:**
- `EVVM_AUTHORIZER_PRIVATE_KEY`: Private key of the authorizer (alternative to `--private-key`)

**Output:**
- Same as Python script

## Integration Flow

### Step 1: Generate Signature

Call the signing script with the required parameters:

```bash
# Python example
python scripts/python/sign_evvm_authorization.py \
  --chain-id 1 \
  --whitelist 0x1234...5678 \
  --agent-id 42 \
  --expires-at 1735689600 \
  --registry 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
```

**Expected output includes:**
```
Signature: 0x<65-byte-signature>
Digest: 0x<32-byte-digest>
```

### Step 2: Store Signature in Registry

Use the signature to call `setMetadata()` on the ERC-8004 Identity Registry:

```bash
cast send <identity_registry_address> \
  "setMetadata(uint256,string,bytes)" \
  <agent_id> \
  "evvmAuthSignature" \
  <signature_hex> \
  --from <agent_owner_address>
```

**Important:** The caller must be the agent owner or have approval.

### Step 3: Pre-Register Agent

Call `preRegisterAgent()` on the validator contract with the **same** expiration time:

```bash
cast send <validator_address> \
  "preRegisterAgent(uint256,uint256)" \
  <agent_id> \
  <expires_at> \
  --from <agent_address>
```

**Critical:** The `expiresAt` value must match exactly what was used in the signature.

### Step 4: Verify Authorization

The validator's `canExecute()` function will:
1. Check if `block.timestamp <= expiresAt`
2. Verify the agent is still the owner/wallet of the agentId
3. Recover the signature and verify it matches the `evvmAuthorizer`

## Data Formats

### Signature Format

- **Length**: 65 bytes (130 hex characters + 0x prefix)
- **Structure**: `r (32 bytes) || s (32 bytes) || v (1 byte)`
- **Standard**: EIP-191 (Ethereum Signed Message)

### Metadata Key

- **Key**: `"evvmAuthSignature"`
- **Value**: 65-byte signature (bytes)

### Timestamp Format

- **Type**: Unix timestamp (seconds since epoch)
- **Example**: `1735689600` = January 1, 2025 00:00:00 UTC

## Chain-Specific Information

### Identity Registry Addresses

**Mainnets** (all use the same address):
- Address: `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`
- Chains: Ethereum, Optimism, BSC, Gnosis, Polygon, XLayer, Abstract, Base, Taiko, Arbitrum, Celo, Avalanche, Mantle, Metis, Scroll, Linea

**Testnets** (all use the same address):
- Address: `0x8004A818BFB912233c491871b3d84c89A494BD9e`
- Chains: Sepolia, Optimism Sepolia, BSC Testnet, Polygon Amoy, Base Sepolia, Arbitrum Sepolia, Avalanche Fuji, Linea Sepolia, Mantle Sepolia, Metis Sepolia, Scroll Sepolia, Hedera Testnet, Celo Alfajores, Soneium Minato

### Chain IDs

Common chain IDs:
- Ethereum Mainnet: `1`
- Sepolia: `11155111`
- Optimism: `10`
- Base: `8453`
- Arbitrum: `42161`
- Polygon: `137`

## Error Handling

### Common Errors

1. **Invalid signature length**
   - Cause: Signature is not 65 bytes
   - Solution: Ensure signature is properly formatted

2. **Signature verification failed**
   - Cause: Digest parameters don't match
   - Solution: Verify all parameters (chainId, whitelist, registry, agentId, expiresAt) are identical

3. **Authorization expired**
   - Cause: `block.timestamp > expiresAt`
   - Solution: Generate new signature with future expiration

4. **Not current agent owner/wallet**
   - Cause: Agent transferred ownership after pre-registration
   - Solution: Re-register with new owner

## Security Considerations

1. **Private Key Management**
   - Never commit private keys to version control
   - Use environment variables or secure key management
   - The authorizer key should be kept secure (it controls all authorizations)

2. **Expiration Times**
   - Set reasonable expiration times (not too short, not too long)
   - Consider clock skew between chains
   - Allow buffer time for transaction confirmation

3. **Signature Replay**
   - Signatures are bound to specific validator contracts
   - Cannot be reused across different validators
   - Expiration prevents indefinite replay

## Example Integration (Python)

```python
import subprocess
import json

def authorize_agent(
    chain_id: int,
    validator_address: str,
    agent_id: int,
    expires_at: int,
    registry_address: str = "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
) -> dict:
    """
    Generate authorization signature for an agent.
    
    Returns:
        dict with 'signature' and 'digest' keys
    """
    result = subprocess.run([
        "python", "scripts/python/sign_evvm_authorization.py",
        "--chain-id", str(chain_id),
        "--whitelist", validator_address,
        "--agent-id", str(agent_id),
        "--expires-at", str(expires_at),
        "--registry", registry_address
    ], capture_output=True, text=True)
    
    output = result.stdout
    
    # Parse signature from output
    signature_line = [line for line in output.split('\n') if line.startswith('Signature:')][0]
    signature = signature_line.split(':')[1].strip()
    
    digest_line = [line for line in output.split('\n') if line.startswith('Digest:')][0]
    digest = digest_line.split(':')[1].strip()
    
    return {
        'signature': signature,
        'digest': digest
    }

# Usage
auth = authorize_agent(
    chain_id=1,
    validator_address="0x1234...5678",
    agent_id=42,
    expires_at=1735689600
)

print(f"Signature: {auth['signature']}")
print(f"Digest: {auth['digest']}")
```

## Example Integration (TypeScript)

```typescript
import { execSync } from 'child_process';

interface AuthorizationResult {
  signature: string;
  digest: string;
}

function authorizeAgent(
  chainId: number,
  validatorAddress: string,
  agentId: number,
  expiresAt: number,
  registryAddress: string = "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
): AuthorizationResult {
  const output = execSync(`
    cd scripts/ts && npm run sign -- \
      --chain-id ${chainId} \
      --whitelist ${validatorAddress} \
      --agent-id ${agentId} \
      --expires-at ${expiresAt} \
      --registry ${registryAddress}
  `, { encoding: 'utf-8' });
  
  // Parse signature from output
  const signatureMatch = output.match(/Signature:\s*(0x[a-fA-F0-9]+)/);
  const digestMatch = output.match(/Digest:\s*(0x[a-fA-F0-9]+)/);
  
  if (!signatureMatch || !digestMatch) {
    throw new Error('Failed to parse signature from output');
  }
  
  return {
    signature: signatureMatch[1],
    digest: digestMatch[1]
  };
}

// Usage
const auth = authorizeAgent(
  1,
  "0x1234...5678",
  42,
  1735689600
);

console.log(`Signature: ${auth.signature}`);
console.log(`Digest: ${auth.digest}`);
```

## Testing

To verify the integration works correctly:

1. Generate a signature with known parameters
2. Store it in the registry
3. Pre-register the agent
4. Call `canExecute()` and verify it returns `true`
5. Wait for expiration and verify it returns `false`

## Support

For issues or questions:
- Check the main README.md for general project information
- Review the contract NatSpec documentation in `contracts/src/`
- Examine the script source code for implementation details

## Version Compatibility

- **Solidity**: ^0.8.0
- **Python**: 3.8+
- **Node.js**: 16+
- **Dependencies**: See `requirements.txt` and `package.json`
