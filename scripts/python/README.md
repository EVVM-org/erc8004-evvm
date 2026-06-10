# Sign EVVM Authorization (Python)

Generates the ECDSA signature for authorizing an ERC-8004 agent in the EVVM whitelist.

## Setup

```bash
pip install -r requirements.txt
```

## Usage

```bash
export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."

python sign_evvm_authorization.py \
    --chain-id 1 \
    --whitelist 0xYourWhitelistContract \
    --agent-id 22
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--chain-id` | Chain ID where whitelist is deployed | `1` |
| `--whitelist` | Whitelist contract address (required) | - |
| `--agent-id` | ERC-8004 agentId to authorize (required) | - |
| `--registry` | ERC-8004 Identity Registry address | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| `--private-key` | EVVM authorizer private key | `$EVVM_AUTHORIZER_PRIVATE_KEY` |

## Output

The script outputs:
- The signature (65 bytes hex)
- The digest that was signed
- A `cast send` example to store the signature onchain

## Onchain Storage

Store the signature in the ERC-8004 Identity Registry:

```bash
cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
    "setMetadata(uint256,string,bytes)" \
    <AGENT_ID> \
    "evvmAuthSignature" \
    <SIGNATURE_HEX> \
    --private-key <AGENT_OWNER_PRIVATE_KEY> \
    --rpc-url <RPC_URL>
```
