// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.org/docs/EVVMNoncommercialLicense
pragma solidity ^0.8.0;

import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

import {
    SignatureRecover
} from "@evvm/testnet-contracts/library/primitives/SignatureRecover.sol";

import {
    AdvancedStrings
} from "@evvm/testnet-contracts/library/utils/AdvancedStrings.sol";

import {
    IdentityRegistryUpgradeable as IdentityRegistry
} from "erc8004/contracts/IdentityRegistryUpgradeable.sol";

/// @title UserValidatorPreRegistrated
/// @notice EVVM user validator using pre-registration and ERC-8004 onchain metadata with signature authorization
/// @dev This contract implements a multi-step validation strategy:
///      1. User must pre-register an agentId with an expiration timestamp
///      2. User must currently be the owner or verified agentWallet of that agentId
///      3. The agent must have metadata key "evvmAuthSignature" in the ERC-8004 registry
///      4. That metadata must be a valid 65-byte ECDSA signature
///      5. The signature must recover to the configured evvmAuthorizer address
///
///      The signature proves: "This agentId is authorized for this exact whitelist contract,
///      on this exact chain, using this exact ERC-8004 Identity Registry, until this expiration time."
///
///      Signature digest construction (matches sign_evvm_authorization.py and sign-evvm-authorization.ts):
///      keccak256(abi.encodePacked("EVVM_AGENT_AUTH", block.chainid, address(this), address(identityRegistry), agentId, expiresAt))
///
///      The digest is converted to a 66-character hex string (with "0x" prefix) and signed using
///      Ethereum Signed Message format: keccak256("\x19Ethereum Signed Message:\n66" || hexString)
///
///      IMPORTANT: The expiresAt timestamp is included in the digest, so the agent must sign with
///      the exact expiration time that will be used during pre-registration.
contract UserValidatorPreRegistrated {
    /// @notice The ERC-8004 Identity Registry used for agent verification and metadata retrieval
    IdentityRegistry immutable identityRegistry;

    /// @notice Administrative address for governance proposals
    ProposalStructs.AddressTypeProposal public admin;

    /// @notice Address whose signatures authorize agents for this EVVM whitelist
    address public immutable evvmAuthorizer;

    /// @notice Metadata key expected in the ERC-8004 Identity Registry for authorization signatures
    string public constant AUTH_METADATA_KEY = "evvmAuthSignature";

    /// @notice Structure holding pre-registration data for a user
    /// @param agentId The ERC-8004 agent identifier that was pre-registered
    /// @param expiresAt Unix timestamp when this authorization expires
    struct PreRegistration {
        uint256 agentId;
        uint256 expiresAt;
    }

    /// @notice Mapping from user address to their pre-registered agent data
    mapping(address => PreRegistration) public preRegisteredAgent;

    /// @notice Emitted when a user successfully pre-registers an agent
    /// @param user The address that pre-registered the agent
    /// @param agentId The ERC-8004 agent identifier that was pre-registered
    event AgentPreRegistered(address indexed user, uint256 indexed agentId);

    /// @notice Emitted when a user removes their pre-registration
    /// @param user The address that removed their pre-registration
    /// @param agentId The ERC-8004 agent identifier that was removed
    event AgentPreRegistrationRemoved(
        address indexed user,
        uint256 indexed agentId
    );

    /// @notice Thrown when a caller is not the current owner or verified agentWallet of an agent
    error NotCurrentAgentOwnerOrWallet();

    /// @notice Creates a new UserValidatorPreRegistrated instance
    /// @param _admin The initial administrator address for governance
    /// @param _identityRegistry Address of the ERC-8004 Identity Registry contract
    /// @param _evvmAuthorizer Address whose signatures authorize agents for this whitelist
    constructor(
        address _admin,
        address _identityRegistry,
        address _evvmAuthorizer
    ) {
        admin.current = _admin;
        identityRegistry = IdentityRegistry(_identityRegistry);
        evvmAuthorizer = _evvmAuthorizer;
    }

    /// @notice Self-service pre-registration of an ERC-8004 agentId for msg.sender
    /// @dev Caller must be either the ownerOf(agentId) or getAgentWallet(agentId) in the registry.
    ///      This is needed because ERC-721 balanceOf tells us "this address owns N agents" but not which agentIds.
    ///      Pre-registration gives this validator a direct address -> agentId mapping.
    /// @param agentId The ERC-8004 agent identifier to pre-register
    /// @param expiresAt Unix timestamp when this authorization expires
    /// @custom:throws NotCurrentAgentOwnerOrWallet If caller is not owner or verified agentWallet
    function preRegisterAgent(
        uint256 agentId,
        uint256 expiresAt
    ) external {
        if (!_isCurrentAgentOwnerOrWallet(msg.sender, agentId)) {
            revert NotCurrentAgentOwnerOrWallet();
        }

        preRegisteredAgent[msg.sender] = PreRegistration({
            agentId: agentId,
            expiresAt: expiresAt
        });

        emit AgentPreRegistered(msg.sender, agentId);
    }

    /// @notice Remove the caller's pre-registration
    /// @dev Deletes the pre-registration entry for msg.sender and emits AgentPreRegistrationRemoved
    function removePreRegistration() external {
        PreRegistration memory current = preRegisteredAgent[msg.sender];

        delete preRegisteredAgent[msg.sender];

        emit AgentPreRegistrationRemoved(msg.sender, current.agentId);
    }

    /// @notice Checks if a user is allowed to execute through the EVVM
    /// @dev Performs the complete 5-step validation:
    ///      1. User has an active pre-registration (not expired)
    ///      2. User is still the current owner or verified agentWallet of the agentId
    ///      3. The agent has metadata key "evvmAuthSignature" in the registry
    ///      4. The metadata is a valid 65-byte ECDSA signature
    ///      5. The signature recovers to the configured evvmAuthorizer
    /// @param user The address to check authorization for
    /// @return allowed True if all validation steps pass, false otherwise
    function canExecute(address user) external view returns (bool allowed) {
        PreRegistration memory reg = preRegisteredAgent[user];

        if (block.timestamp > reg.expiresAt) return false;

        if (!_isCurrentAgentOwnerOrWallet(user, reg.agentId)) return false;

        bytes memory signature;

        try
            identityRegistry.getMetadata(reg.agentId, AUTH_METADATA_KEY)
        returns (bytes memory result) {
            signature = result;
        } catch {
            return false;
        }

        return
            SignatureRecover.recoverSigner(
                AdvancedStrings.bytes32ToString(
                    keccak256(
                        abi.encodePacked(
                            "EVVM_AGENT_AUTH",
                            block.chainid,
                            address(this),
                            address(identityRegistry),
                            reg.agentId,
                            reg.expiresAt
                        )
                    )
                ),
                signature
            ) == evvmAuthorizer;
    }

    /// @notice Helper for demos and UIs to retrieve the registered agentId for a user
    /// @param user The address to query
    /// @return active Whether the user has an active pre-registration (not expired)
    /// @return agentId The ERC-8004 agent identifier (meaningful only if active is true)
    function registeredAgentIdOf(
        address user
    ) external view returns (bool active, uint256 agentId) {
        PreRegistration memory reg = preRegisteredAgent[user];
        return (block.timestamp <= reg.expiresAt, reg.agentId);
    }

    /// @notice Checks if an account is currently the agent owner or verified agent wallet
    /// @dev Queries the ERC-8004 Identity Registry for ownerOf() and getAgentWallet()
    /// @param account The address to check
    /// @param agentId The ERC-8004 agent identifier to verify against
    /// @return True if account is owner or verified agentWallet of agentId, false otherwise
    function _isCurrentAgentOwnerOrWallet(
        address account,
        uint256 agentId
    ) internal view returns (bool) {
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
}
