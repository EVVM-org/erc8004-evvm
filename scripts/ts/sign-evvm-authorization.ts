#!/usr/bin/env tsx
/**
 * Creates the EVVM authorization signature for an ERC-8004 agent.
 *
 * This script generates an ECDSA signature that authorizes an ERC-8004 agent
 * to execute through the EVVM whitelist system. The signature is stored as
 * onchain metadata in the official ERC-8004 Identity Registry.
 *
 * ## Metadata Convention
 *
 * Used by `UserValidatorPreRegistrated.sol`:
 *
 *     metadataKey   = "evvmAuthSignature"
 *     metadataValue = <65-byte ECDSA signature>
 *
 * ## Signature Semantics
 *
 * The signature attests:
 *
 *     "This ERC-8004 agentId is authorized for this exact EVVM whitelist."
 *
 * ## Digest Construction
 *
 * The signed digest matches the Solidity implementation:
 *
 *     keccak256(
 *         abi.encodePacked(
 *             "EVVM_AGENT_AUTH",
 *             block.chainid,
 *             address(whitelist),
 *             address(identityRegistry),
 *             agentId,
 *             block.timestamp
 *         )
 *     )
 *
 * The resulting 32-byte digest is converted to a 66-character hex string
 * (with `0x` prefix) and signed using the Ethereum Signed Message format:
 *
 *     keccak256("\x19Ethereum Signed Message:\n66" || hexString)
 *
 * IMPORTANT: The timestamp in the signature MUST match the block.timestamp
 * when the transaction is mined. Use --target-timestamp to specify the exact
 * timestamp of the target block.
 *
 * ## Installation
 *
 *     npm install
 *
 * ## Usage
 *
 *     export EVVM_AUTHORIZER_PRIVATE_KEY="0x..."
 *
 *     npm run sign -- \
 *         --chain-id 1 \
 *         --whitelist 0xYourWhitelistEVVMContract \
 *         --agent-id 22
 *
 * ### Options
 *
 * | Option          | Description                                      | Default      |
 * |-----------------|--------------------------------------------------|--------------|
 * | --chain-id      | Chain ID where the whitelist is deployed         | 1            |
 * | --whitelist     | Whitelist contract address (required)            | -            |
 * | --agent-id      | ERC-8004 agentId to authorize (required)         | -            |
 * | --registry      | ERC-8004 Identity Registry address               | 0x8004...    |
 * | --private-key   | EVVM authorizer private key                      | env var      |
 *
 * ## Onchain Storage
 *
 * After generating the signature, store it in the ERC-8004 Identity Registry:
 *
 *     cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
 *         "setMetadata(uint256,string,bytes)" \
 *         <AGENT_ID> \
 *         "evvmAuthSignature" \
 *         <SIGNATURE_HEX> \
 *         --private-key <AGENT_OWNER_PRIVATE_KEY> \
 *         --rpc-url <ETHEREUM_MAINNET_RPC_URL>
 *
 * ## Important Notes
 *
 * - The signer in `EVVM_AUTHORIZER_PRIVATE_KEY` must match the `evvmAuthorizer`
 *   configured in `UserValidatorPreRegistrated`.
 * - The metadata transaction must be sent by whoever has permission to update
 *   the agent metadata in the ERC-8004 Identity Registry.
 *
 * @module sign-evvm-authorization
 */

import { parseArgs } from "node:util";
import {
  createWalletClient,
  http,
  keccak256,
  encodePacked,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { mainnet } from "viem/chains";

/** Default ERC-8004 Identity Registry on Ethereum Mainnet */
const DEFAULT_ETHEREUM_MAINNET_IDENTITY_REGISTRY: Address =
  "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432";

/** Metadata key used in the ERC-8004 Identity Registry */
const METADATA_KEY = "evvmAuthSignature";

/** Average block times in seconds for common chains */
const CHAIN_BLOCK_TIMES: Record<number, number> = {
  1: 12,        // Ethereum
  10: 2,        // Optimism
  56: 3,        // BSC
  137: 2,       // Polygon
  8453: 2,      // Base
  42161: 0.25,  // Arbitrum
  43114: 2,     // Avalanche
  100: 5,       // Gnosis
  11155111: 12, // Sepolia
};

/**
 * Parsed command-line arguments.
 */
interface Args {
  /** Chain ID where the whitelist contract is deployed */
  chainId: number;
  /** Address of the UserValidatorPreRegistrated contract */
  whitelist: Address;
  /** ERC-8004 agent identifier to authorize */
  agentId: number;
  /** Address of the ERC-8004 Identity Registry */
  registry: Address;
  /** Private key of the EVVM authorizer (with 0x prefix) */
  privateKey: string;
  /** Target block number for execution (optional) */
  targetBlock?: number;
  /** Target Unix timestamp (required, must match block.timestamp) */
  targetTimestamp: number;
}

/**
 * Parse and validate command-line arguments.
 *
 * Reads from CLI flags or falls back to environment variables:
 * - `--private-key` or `EVVM_AUTHORIZER_PRIVATE_KEY`
 *
 * @returns Parsed arguments object
 * @throws {never} Exits process if required arguments are missing
 */
function parseCliArgs(): Args {
  const { values } = parseArgs({
    options: {
      "chain-id": { type: "string", default: "1" },
      whitelist: { type: "string" },
      "agent-id": { type: "string" },
      registry: { type: "string", default: DEFAULT_ETHEREUM_MAINNET_IDENTITY_REGISTRY },
      "private-key": { type: "string" },
      "target-block": { type: "string" },
      "target-timestamp": { type: "string" },
    },
  });

  const privateKey =
    values["private-key"] || process.env.EVVM_AUTHORIZER_PRIVATE_KEY;

  if (!privateKey) {
    console.error(
      "Missing private key. Set EVVM_AUTHORIZER_PRIVATE_KEY or pass --private-key."
    );
    process.exit(1);
  }

  if (!values.whitelist) {
    console.error("Missing --whitelist address.");
    process.exit(1);
  }

  if (!values["agent-id"]) {
    console.error("Missing --agent-id.");
    process.exit(1);
  }

  if (!values["target-timestamp"]) {
    console.error("Missing --target-timestamp (must match block.timestamp when tx is mined).");
    process.exit(1);
  }

  return {
    chainId: parseInt(values["chain-id"]!, 10),
    whitelist: values.whitelist as Address,
    agentId: parseInt(values["agent-id"]!, 10),
    registry: values.registry as Address,
    privateKey: privateKey.startsWith("0x")
      ? privateKey
      : `0x${privateKey}`,
    targetBlock: values["target-block"] ? parseInt(values["target-block"], 10) : undefined,
    targetTimestamp: parseInt(values["target-timestamp"], 10),
  };
}

/**
 * Compute the authorization digest matching Solidity's canExecute() digest.
 *
 * The digest is computed as:
 *
 *     keccak256(
 *         abi.encodePacked(
 *             "EVVM_AGENT_AUTH",
 *             chainId,
 *             whitelist,
 *             registry,
 *             agentId,
 *             timestamp
 *         )
 *     )
 *
 * @param chainId - Chain ID where the whitelist contract is deployed
 * @param whitelist - Address of the whitelist contract
 * @param registry - Address of the ERC-8004 Identity Registry
 * @param agentId - The ERC-8004 agent identifier
 * @param timestamp - Block timestamp when the transaction will be mined
 * @returns 32-byte digest as hex string with 0x prefix
 */
function computeAuthorizationDigest(
  chainId: number,
  whitelist: Address,
  registry: Address,
  agentId: number,
  timestamp: number
): `0x${string}` {
  return keccak256(
    encodePacked(
      ["string", "uint256", "address", "address", "uint256", "uint256"],
      ["EVVM_AGENT_AUTH", BigInt(chainId), whitelist, registry, BigInt(agentId), BigInt(timestamp)]
    )
  );
}

/**
 * Print the authorization result in a human-readable format.
 *
 * @param params - Output parameters
 * @param params.authorizerAddress - Address of the EVVM authorizer
 * @param params.chainId - Chain ID where the whitelist is deployed
 * @param params.whitelist - Address of the whitelist contract
 * @param params.registry - Address of the ERC-8004 Identity Registry
 * @param params.agentId - The ERC-8004 agent identifier
 * @param params.timestamp - Block timestamp used in the signature
 * @param params.signature - Hex-encoded signature
 * @param params.digest - Original 32-byte digest (hex string)
 * @param params.digestHex - Hex string representation of the digest (66 chars)
 * @param params.targetBlock - Target block number for execution (optional)
 */
function printAuthorizationOutput(params: {
  authorizerAddress: Address;
  chainId: number;
  whitelist: Address;
  registry: Address;
  agentId: number;
  timestamp: number;
  signature: `0x${string}`;
  digest: `0x${string}`;
  digestHex: string;
  targetBlock?: number;
}): void {
  const {
    authorizerAddress,
    chainId,
    whitelist,
    registry,
    agentId,
    timestamp,
    signature,
    digest,
    digestHex,
    targetBlock,
  } = params;

  console.log("=== EVVM ERC-8004 Agent Authorization ===");
  console.log();
  console.log(`EVVM authorizer address: ${authorizerAddress}`);
  console.log(`Chain ID:                ${chainId}`);
  console.log(`Whitelist contract:      ${whitelist}`);
  console.log(`Identity Registry:       ${registry}`);
  console.log(`Agent ID:                ${agentId}`);
  console.log(`Timestamp (block.timestamp): ${timestamp}`);
  console.log();
  console.log("Metadata key:");
  console.log(METADATA_KEY);
  console.log();
  console.log("Metadata value / signature:");
  console.log(signature);
  console.log();
  console.log("Digest (bytes32):");
  console.log(digest);
  console.log();
  console.log("Message signed (hex string, 66 chars):");
  console.log(digestHex);
  console.log();
  console.log("Foundry cast example:");
  console.log(
    `cast send ${registry} ` +
      '"setMetadata(uint256,string,bytes)" ' +
      `${agentId} ` +
      `"${METADATA_KEY}" ` +
      `${signature} ` +
      "--private-key <AGENT_OWNER_PRIVATE_KEY> " +
      "--rpc-url <ETHEREUM_MAINNET_RPC_URL>"
  );

  if (targetBlock !== undefined) {
    printTimingInfo(chainId, targetBlock, timestamp);
  } else {
    printTimingInfo(chainId, undefined, timestamp);
  }
}

/**
 * Calculate and print timing information for the agent.
 *
 * @param chainId - Chain ID where the transaction will be sent
 * @param targetBlock - Target block number for execution (optional)
 * @param targetTimestamp - Target Unix timestamp (already used in signature)
 */
function printTimingInfo(
  chainId: number,
  targetBlock?: number,
  targetTimestamp?: number
): void {
  const blockTime = CHAIN_BLOCK_TIMES[chainId] || 12;
  const currentTime = Math.floor(Date.now() / 1000);
  const currentDate = new Date(currentTime * 1000).toISOString();

  console.log();
  console.log("=== Agent Timing Information ===");
  console.log(`Chain ID: ${chainId}`);
  console.log(`Average block time: ${blockTime}s`);
  console.log(`Current time: ${currentTime} (${currentDate})`);
  if (targetTimestamp) {
    const signedDate = new Date(targetTimestamp * 1000).toISOString();
    console.log(`Signed timestamp: ${targetTimestamp} (${signedDate})`);
  }

  if (targetTimestamp !== undefined) {
    const secondsUntil = targetTimestamp - currentTime;
    const submitTime = currentTime + Math.max(0, secondsUntil - Math.floor(blockTime));
    const targetDate = new Date(targetTimestamp * 1000).toISOString();
    const submitDate = new Date(submitTime * 1000).toISOString();

    console.log();
    console.log(`Target timestamp: ${targetTimestamp} (${targetDate})`);
    console.log(`Seconds until target: ${secondsUntil}`);
    console.log(`Recommended submit time: ${submitTime} (${submitDate})`);
    console.log(`Submit ${Math.floor(blockTime)}s before target to hit the block`);
    console.log("IMPORTANT: block.timestamp MUST match the signed timestamp exactly!");
  }

  if (targetBlock !== undefined) {
    console.log();
    console.log(`Target block: ${targetBlock}`);
    console.log("Note: Use an RPC to get current block number and calculate submission timing");
    console.log(`Formula: submit_time = now + (target_block - current_block) * ${blockTime}s`);
  }
}

/**
 * Main entry point for the authorization signing script.
 *
 * Orchestrates the complete flow:
 * 1. Parse and validate CLI arguments
 * 2. Compute the authorization digest
 * 3. Sign the hex string representation using EIP-191
 * 4. Output results and usage examples
 *
 * @returns Promise that resolves when signing is complete
 * @throws {Error} If signing fails or arguments are invalid
 */
async function main(): Promise<void> {
  const args = parseCliArgs();

  const account = privateKeyToAccount(args.privateKey as `0x${string}`);

  const walletClient = createWalletClient({
    account,
    chain: mainnet,
    transport: http(),
  });

  // Compute digest matching Solidity's canExecute() digest
  const digest = computeAuthorizationDigest(
    args.chainId,
    args.whitelist,
    args.registry,
    args.agentId,
    args.targetTimestamp
  );

  // The digest is already a hex string (0x + 64 hex chars = 66 chars)
  // This matches Solidity's AdvancedStrings.bytes32ToString()
  const digestHexString = digest;

  // Sign using EIP-191, matching Solidity's SignatureRecover.recoverSigner()
  const signature = await walletClient.signMessage({
    message: digestHexString,
  });

  printAuthorizationOutput({
    authorizerAddress: account.address,
    chainId: args.chainId,
    whitelist: args.whitelist,
    registry: args.registry,
    agentId: args.agentId,
    timestamp: args.targetTimestamp,
    signature,
    digest,
    digestHex: digestHexString,
    targetBlock: args.targetBlock,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
