// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {
    CoreStructs as Structs
} from "@evvm/testnet-contracts/library/structs/CoreStructs.sol";

import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

/**
 * @title CoreStorage
 * @author Mate labs
 * @notice Centralized storage layout for the EVVM Core contract.
 * @dev Designed for use with proxy patterns. This contract must remain append-only
 *      to maintain storage slots across upgrades.
 */
abstract contract CoreStorage {
    //░▒▓█ Constants ██████████████████████████████████████████████████████████████████▓▒░

    /**
     * @notice Sentinel address representing native ETH (or the chain's native token).
     */
    address constant ETH_ADDRESS = address(0);

    /**
     * @notice Flag indicating an address is a registered staker.
     * @dev Value 0x01 is used in stakerList to signify active status.
     */
    bytes1 constant FLAG_IS_STAKER = 0x01;

    /**
     * @notice Minimum time delay (1 day) to accept a proposed admin change.
     */
    uint256 constant TIME_TO_ACCEPT_PROPOSAL = 1 days;

    /**
     * @notice Minimum time delay (30 days) to accept a proposed implementation upgrade.
     */
    uint256 constant TIME_TO_ACCEPT_IMPLEMENTATION = 30 days;

    //░▒▓█ External Contract Addresses █████████████████████████████████████████████████▓▒░

    /**
     * @notice Address of the EVVM NameService for identity and username resolution.
     */
    address nameServiceAddress;

    /**
     * @notice Address of the Staking contract.
     * @dev Authorized to update staker status and manage reward distributions.
     */
    address stakingContractAddress;

    /**
     * @notice Address of the Treasury contract.
     * @dev Authorized for privileged balance operations (add/remove tokens).
     */
    address treasuryAddress;

    //░▒▓█ Proxy Implementation State ██████████████████████████████████████████████████▓▒░

    /**
     * @notice Current active implementation address.
     * @dev Used by the fallback function for delegatecall.
     */
    address currentImplementation;

    /**
     * @notice Proposed future implementation address.
     */
    address proposalImplementation;

    /**
     * @notice Timestamp after which the proposed implementation can be finalized.
     */
    uint256 timeToAcceptImplementation;

    //░▒▓█ Total supply ██████████████████████████████████████████████████▓▒░

    /**
     * @notice Timestamp after which the maximum supply can be deleted.
     */
    uint256 timeToDeleteMaxSupply;

    //░▒▓█ EVVM Configuration State ████████████████████████████████████████████████████▓▒░

    /**
     * @notice Timestamp limiting when the EVVM ID can be modified (initial window).
     */
    uint256 windowTimeToChangeEvvmID;

    /**
     * @notice Current total supply of the principal token within the EVVM.
     */
    uint256 currentSupply;

    /**
     * @notice Metadata configuration for this EVVM instance (ID, token info, rewards).
     * @dev Crucial for EIP-191 signature verification to prevent replay attacks.
     */
    Structs.EvvmMetadata evvmMetadata;

    //░▒▓█ Admin Governance State ██████████████████████████████████████████████████████▓▒░

    /**
     * @notice Management of the admin role with time-delayed transitions.
     */
    ProposalStructs.AddressTypeProposal admin;

    //░▒▓█ Reward Distribution State ██████████████████████████████████████████████████████▓▒░

    /**
     * @notice Governance-controlled flag to enable or disable staking reward distribution.
     * @dev Defaults to true. Can only be toggled via governance once 99.99% of supply is minted.
     */
    ProposalStructs.BoolTypeProposal rewardFlowDistribution;

    uint256 proposalChangeReward;
    uint256 timeToAcceptChangeReward;

    //░▒▓█ List state ████████████████████████████████████████████████████████▓▒░

    /**
     * @notice Indicates if the EVVM nees to check the allowlist or the denylist for token operations.
     * @dev 0x00 = no lists active
     *      0x01 = allowlist active
     *      0x02 = denylist active
     */
    ProposalStructs.Bytes1TypeProposal listStatus;

    //░▒▓█ Initialization State ████████████████████████████████████████████████████████▓▒░

    /**
     * @notice Internal guard to ensure system contracts are initialized only once.
     */
    bool breakerSetupNameServiceAddress;

    //░▒▓█ Staker Registry █████████████████████████████████████████████████████████████▓▒░

    /**
     * @notice Tracks addresses registered as active stakers.
     */
    mapping(address => bytes1) stakerList;

    //░▒▓█ Balance Management ██████████████████████████████████████████████████████████▓▒░

    /**
     * @notice Internal ledger of user balances across different tokens.
     * @dev Format: user => token => balance. address(0) = ETH.
     */
    mapping(address user => mapping(address token => uint256 quantity)) balances;

    //░▒▓█ Nonce State ██████████████████████████████████████████████████████████▓▒░

    /**
     * @notice Proposal state for the active UserValidator contract address.
     */
    ProposalStructs.AddressTypeProposal userValidatorAddress;

    /**
     * @notice tracks if a specific async nonce has already been consumed.
     * @dev Async nonces allow parallel execution as they can be used in any order.
     */
    mapping(address user => mapping(uint256 nonce => bool isUsed)) asyncNonce;

    /**
     * @notice Reserves an async nonce for a specific service address.
     * @dev Prevents different services from attempting to use the same user nonce simultaneously.
     */
    mapping(address user => mapping(uint256 nonce => address serviceReserved)) asyncNonceReservedPointers;

    /**
     * @notice tracks the next expected nonce for sequential (synchronous) transactions.
     */
    mapping(address user => uint256 nonce) nextSyncNonce;

    //░▒▓█ Token allowlist/denylist ██████████████████████████████████████████████████████████▓▒░

    /**
     * @notice Token denylist. Restricted tokens cannot be deposited or transferred, but can still be withdrawn.
     * @dev Active when listStatus = 0x02.
     */
    mapping(address tokenAdress => bool isDenied) denyList;

    /**
     * @notice Token allowlist. Only listed tokens can be deposited and transferred.
     * @dev Active when listStatus = 0x01.
     */
    mapping(address tokenAdress => bool isAllowed) allowList;
}
