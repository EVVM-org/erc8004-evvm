// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title WhitelistEVVM_PreRegisteredERC8004
 * @notice Example 2: EVVM whitelist using pre-registration + ERC-8004 onchain metadata.
 *
 * Goal:
 * - Use the real ERC-8004 Identity Registry.
 * - Do not deploy a custom registry.
 * - Allow an agent owner or verified agent wallet to pre-register an agentId.
 * - Later, EVVM calls canExecute(user), and this contract checks:
 *      1. user pre-registered an agentId;
 *      2. user is still the current owner or verified agentWallet of that agentId;
 *      3. the agent has metadata key "evvmAuthSignature" in the ERC-8004 registry;
 *      4. that metadata value is a valid signature by evvmAuthorizer;
 *      5. the signed message is specific to this chain, this whitelist, this registry and this agentId.
 *
 * Why this is useful:
 * - It upgrades the whitelist from "wallet address yes/no" to
 *   "registered agent with EVVM-specific authorization yes/no".
 *
 * Registry:
 * - Uses the real ERC-8004 Identity Registry on Ethereum Mainnet by default:
 *   0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
 *
 * Metadata convention for the demo:
 * - metadataKey   = "evvmAuthSignature"
 * - metadataValue = bytes signature created by the EVVM authorizer offchain.
 *
 * Signature meaning:
 * - The EVVM authorizer signs:
 *      keccak256(
 *          abi.encodePacked(
 *              "EVVM_AGENT_AUTH",
 *              block.chainid,
 *              address(this),
 *              address(identityRegistry),
 *              agentId
 *          )
 *      )
 *
 * - This proves:
 *      "This agentId is authorized for this exact whitelist contract,
 *       on this exact chain, using this exact ERC-8004 Identity Registry."
 *
 * Important:
 * - This contract must run on the same chain where the registry exists.
 * - If EVVM runs elsewhere, it needs a native read mechanism, mirror, oracle,
 *   bridge, or equivalent same-chain deployment of the official registry.
 *
 * Production note:
 * - This is intentionally simple for workshop/demo use.
 * - For production, prefer audited ECDSA helpers such as OpenZeppelin ECDSA,
 *   add admin controls, revocation strategy, expiry/deadline, and richer policy logic.
 */

interface IERC8004IdentityRegistryMinimal {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function getAgentWallet(uint256 agentId) external view returns (address wallet);
    function getMetadata(uint256 agentId, string calldata metadataKey) external view returns (bytes memory metadataValue);
}

contract WhitelistEVVM_PreRegisteredERC8004 {
    /// @notice Official ERC-8004 Identity Registry on Ethereum Mainnet.
    address public constant ETHEREUM_MAINNET_ERC8004_IDENTITY_REGISTRY =
        0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;

    /// @notice Metadata key expected in the ERC-8004 Identity Registry.
    string public constant AUTH_METADATA_KEY = "evvmAuthSignature";

    IERC8004IdentityRegistryMinimal public immutable identityRegistry;

    /// @notice Address allowed to authorize agents for this EVVM whitelist.
    address public immutable evvmAuthorizer;

    struct PreRegistration {
        bool active;
        uint256 agentId;
    }

    /// @notice user address => pre-registered ERC-8004 agentId.
    mapping(address => PreRegistration) public preRegisteredAgent;

    event AgentPreRegistered(address indexed user, uint256 indexed agentId);
    event AgentPreRegistrationRemoved(address indexed user, uint256 indexed agentId);

    error ZeroAddress();
    error InvalidAgent();
    error NotCurrentAgentOwnerOrWallet();

    /**
     * @notice Deploy using the official Ethereum Mainnet registry by passing address(0).
     * @param identityRegistry_ ERC-8004 Identity Registry address. Use address(0) for Mainnet official.
     * @param evvmAuthorizer_ Wallet whose signatures authorize agents for this EVVM whitelist.
     */
    constructor(address identityRegistry_, address evvmAuthorizer_) {
        address registry = identityRegistry_ == address(0)
            ? ETHEREUM_MAINNET_ERC8004_IDENTITY_REGISTRY
            : identityRegistry_;

        if (registry == address(0) || evvmAuthorizer_ == address(0)) {
            revert ZeroAddress();
        }

        identityRegistry = IERC8004IdentityRegistryMinimal(registry);
        evvmAuthorizer = evvmAuthorizer_;
    }

    /**
     * @notice Self pre-register an ERC-8004 agentId for msg.sender.
     *
     * Requirements:
     * - agentId must exist in the official Identity Registry.
     * - msg.sender must currently be either:
     *      1. ownerOf(agentId), or
     *      2. getAgentWallet(agentId)
     *
     * Why this is needed:
     * - With only an address, ERC-721 balanceOf tells us "this address owns N agents",
     *   but not which agentIds.
     * - Pre-registration gives this whitelist a direct address -> agentId mapping.
     */
    function preRegisterAgent(uint256 agentId) external {
        if (!_isCurrentAgentOwnerOrWallet(msg.sender, agentId)) {
            revert NotCurrentAgentOwnerOrWallet();
        }

        preRegisteredAgent[msg.sender] = PreRegistration({
            active: true,
            agentId: agentId
        });

        emit AgentPreRegistered(msg.sender, agentId);
    }

    /**
     * @notice Remove caller's pre-registration.
     */
    function removePreRegistration() external {
        PreRegistration memory current = preRegisteredAgent[msg.sender];

        delete preRegisteredAgent[msg.sender];

        emit AgentPreRegistrationRemoved(msg.sender, current.agentId);
    }

    /**
     * @notice EVVM-facing binary check.
     *
     * Returns false if:
     * - user never pre-registered;
     * - user is no longer owner or verified agentWallet of the agentId;
     * - metadata is missing;
     * - metadata is not a 65-byte ECDSA signature;
     * - signature does not recover evvmAuthorizer.
     */
    function canExecute(address user) external view returns (bool allowed) {
        if (user == address(0)) {
            return false;
        }

        PreRegistration memory reg = preRegisteredAgent[user];

        if (!reg.active) {
            return false;
        }

        if (!_isCurrentAgentOwnerOrWallet(user, reg.agentId)) {
            return false;
        }

        bytes memory signature;

        try identityRegistry.getMetadata(reg.agentId, AUTH_METADATA_KEY) returns (bytes memory result) {
            signature = result;
        } catch {
            return false;
        }

        if (signature.length != 65) {
            return false;
        }

        bytes32 digest = authorizationDigest(reg.agentId);
        bytes32 ethSignedDigest = toEthSignedMessageHash(digest);

        return recoverSigner(ethSignedDigest, signature) == evvmAuthorizer;
    }

    /**
     * @notice Digest that the EVVM authorizer signs offchain.
     * @dev Must match the Python script exactly.
     */
    function authorizationDigest(uint256 agentId) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "EVVM_AGENT_AUTH",
                block.chainid,
                address(this),
                address(identityRegistry),
                agentId
            )
        );
    }

    /**
     * @notice Helper for demos/UI: returns the registered agentId for a user.
     */
    function registeredAgentIdOf(address user) external view returns (bool active, uint256 agentId) {
        PreRegistration memory reg = preRegisteredAgent[user];
        return (reg.active, reg.agentId);
    }

    /**
     * @notice Checks if account is currently the agent owner or verified agent wallet.
     */
    function _isCurrentAgentOwnerOrWallet(address account, uint256 agentId) internal view returns (bool) {
        if (account == address(0)) {
            return false;
        }

        address owner;

        try identityRegistry.ownerOf(agentId) returns (address result) {
            owner = result;
        } catch {
            return false;
        }

        if (account == owner) {
            return true;
        }

        address agentWallet;

        try identityRegistry.getAgentWallet(agentId) returns (address result) {
            agentWallet = result;
        } catch {
            return false;
        }

        return agentWallet != address(0) && account == agentWallet;
    }

    /**
     * @notice Ethereum signed message hash for a 32-byte digest.
     * @dev Must match eth_account.messages.encode_defunct(primitive=digest).
     */
    function toEthSignedMessageHash(bytes32 digest) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
        );
    }

    /**
     * @notice Minimal ECDSA recover for 65-byte signatures.
     * @dev Demo implementation. Use OpenZeppelin ECDSA in production.
     */
    function recoverSigner(bytes32 ethSignedDigest, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        return ecrecover(ethSignedDigest, v, r, s);
    }
}
