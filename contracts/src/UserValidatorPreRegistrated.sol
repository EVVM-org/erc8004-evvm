// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

import {
    IdentityRegistryUpgradeable as IdentityRegistry
} from "erc8004/contracts/IdentityRegistryUpgradeable.sol";

contract UserValidatorPreRegistrated {
    IdentityRegistry immutable identityRegistry;
    ProposalStructs.AddressTypeProposal public admin;
    address public immutable evvmAuthorizer;

    string public constant AUTH_METADATA_KEY = "evvmAuthSignature";

    struct PreRegistration {
        bool active;
        uint256 agentId;
    }

    mapping(address => PreRegistration) public preRegisteredAgent;

    event AgentPreRegistered(address indexed user, uint256 indexed agentId);
    event AgentPreRegistrationRemoved(address indexed user, uint256 indexed agentId);

    error NotCurrentAgentOwnerOrWallet();

    constructor(address _admin, address _identityRegistry, address _evvmAuthorizer) {
        admin.current = _admin;
        identityRegistry = IdentityRegistry(_identityRegistry);
        evvmAuthorizer = _evvmAuthorizer;
    }

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

    function removePreRegistration() external {
        PreRegistration memory current = preRegisteredAgent[msg.sender];

        delete preRegisteredAgent[msg.sender];

        emit AgentPreRegistrationRemoved(msg.sender, current.agentId);
    }

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

    function registeredAgentIdOf(address user) external view returns (bool active, uint256 agentId) {
        PreRegistration memory reg = preRegisteredAgent[user];
        return (reg.active, reg.agentId);
    }

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

    function toEthSignedMessageHash(bytes32 digest) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
        );
    }

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
