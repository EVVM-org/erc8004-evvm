// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

import {
    IdentityRegistryUpgradeable as IdentityRegistry
} from "erc8004/contracts/IdentityRegistryUpgradeable.sol";

contract UserValidator {
    IdentityRegistry immutable identityRegistry;
    ProposalStructs.AddressTypeProposal public admin;

    constructor(address _admin, address _identityRegistry) {
        admin.current = _admin;
        identityRegistry = IdentityRegistry(_identityRegistry);
    }

    function canExecute(address user) external view returns (bool allowed) {
        try identityRegistry.balanceOf(user) returns (uint256 balance) {
            return balance > 0;
        } catch {
            return false;
        }
    }
}
