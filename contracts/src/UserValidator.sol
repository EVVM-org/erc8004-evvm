// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.org/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

import {
    IdentityRegistryUpgradeable as IdentityRegistry
} from "erc8004/contracts/IdentityRegistryUpgradeable.sol";

/// @title UserValidator
/// @notice EVVM user validator that checks if a user owns at least one ERC-8004 agent
/// @dev This is the simplest validation strategy using only balanceOf() from the ERC-8004 Identity Registry.
/// It proves that a given address owns registered agents, but cannot identify which specific agentIds.
contract UserValidator {
    /// @notice The ERC-8004 Identity Registry used for agent ownership verification
    IdentityRegistry immutable identityRegistry;

    /// @notice Administrative address for governance proposals
    ProposalStructs.AddressTypeProposal public admin;

    /// @notice Creates a new UserValidator instance
    /// @param _admin The initial administrator address for governance
    /// @param _identityRegistry Address of the ERC-8004 Identity Registry contract
    constructor(address _admin, address _identityRegistry) {
        admin.current = _admin;
        identityRegistry = IdentityRegistry(_identityRegistry);
    }

    /// @notice Checks if a user is allowed to execute through the EVVM
    /// @dev Returns true if the user owns at least one ERC-8004 agent (balanceOf > 0)
    /// @param user The address to check for agent ownership
    /// @return allowed True if user owns one or more registered agents, false otherwise
    function canExecute(address user) external view returns (bool allowed) {
        try identityRegistry.balanceOf(user) returns (uint256 balance) {
            return balance > 0;
        } catch {
            return false;
        }
    }
}
