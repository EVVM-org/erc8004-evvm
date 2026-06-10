# EVVM + ERC-8004 Official Registry Whitelist Examples

These files are for the EVVM workshop demo.

They do **not** deploy a custom ERC-8004 registry.

They use the official Ethereum Mainnet ERC-8004 Identity Registry by default:

`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`

## Files

### 1. WhitelistEVVM_BasicERC8004.sol

Minimal example:

```solidity
canExecute(user) = identityRegistry.balanceOf(user) > 0
```

This proves that with only an address, an EVVM whitelist can know whether the
address owns one or more registered ERC-8004 agents.

Limitation:

- It cannot list agentIds from only an address in the ERC-721 base interface.

### 2. WhitelistEVVM_PreRegisteredERC8004.sol

Pre-registration example:

1. Agent calls `preRegisterAgent(agentId)`.
2. Contract checks that caller is `ownerOf(agentId)` or `getAgentWallet(agentId)`.
3. EVVM calls `canExecute(user)`.
4. Contract checks metadata key `evvmAuthSignature`.
5. Contract verifies that the signature was produced by the EVVM authorizer.

### 3. sign_evvm_authorization.py

Creates the EVVM authorizer signature to store in ERC-8004 metadata:

```text
metadataKey   = evvmAuthSignature
metadataValue = signature bytes
```

Example:

```bash
export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."

python sign_evvm_authorization.py \
  --chain-id 1 \
  --whitelist 0xYourWhitelistContract \
  --agent-id 22
```

Then the agent owner stores the signature in the official registry:

```bash
cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
  "setMetadata(uint256,string,bytes)" \
  22 \
  "evvmAuthSignature" \
  0xSignatureHex \
  --private-key <AGENT_OWNER_PRIVATE_KEY> \
  --rpc-url <ETHEREUM_MAINNET_RPC_URL>
```

## Important

A Solidity contract can only directly read contracts on its own chain.

For this demo, if the whitelist points to the official Ethereum Mainnet registry,
the whitelist must also be executed in an Ethereum-readable context.

If EVVM is on another chain, use a same-chain official deployment, mirror, oracle,
bridge, state proof mechanism, or equivalent read layer.
