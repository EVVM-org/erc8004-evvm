// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

/**
 * @title CoreError - Error Definitions for EVVM Core
 * @author Mate labs
 * @notice Custom error definitions for Core.sol core contract
 * @dev Gas-efficient custom errors for all Core.sol failure conditions.
 */
library CoreError {
    //░▒▓█ Access Control Errors ████████████████████████████████████████████████▓▒░

    /// @dev Thrown when non-admin calls admin-only function (onlyAdmin modifier)
    error SenderIsNotAdmin();

    /// @dev Thrown when proxy implementation == address(0)
    error ImplementationIsNotActive();

    /// @dev Thrown when EIP-191 signature invalid or signer mismatch
    error InvalidSignature();

    /// @dev Thrown when msg.sender != sender executor address
    error SenderIsNotTheSenderExecutor();

    /// @dev Thrown when non-treasury calls treasury-only function
    error SenderIsNotTreasury();

    /// @dev Thrown when non-proposed admin attempts acceptAdmin before timelock
    error SenderIsNotTheProposedAdmin();

    error OriginMismatch();

    /// @dev Thrown when EOA calls caPay/disperseCaPay (contract-only functions)
    error NotAnCA();

    //░▒▓█ Balance and Amount Errors ████████████████████████████████████████████▓▒░

    /// @dev Thrown when balance < transfer amount
    error InsufficientBalance();

    /// @dev Thrown when amount validation fails (e.g., dispersePay total != sum)
    error InvalidAmount();

    //░▒▓█ Initialization and Setup Errors ██████████████████████████████████████▓▒░

    /// @dev Thrown when one-time setup function called after breaker flag set
    error BreakerExploded();

    /// @dev Thrown when attempting EVVM ID change after 24h window
    error WindowExpired();

    /// @dev Thrown when address(0) provided (constructor, setup)
    error AddressCantBeZero();

    /// @dev Thrown when address validation fails in proposals
    error IncorrectAddressInput();

    //░▒▓█ Proposal Errors █████████████████████████████████████████████████████▓▒░

    /// @dev Thrown when accepting before timelock
    error ProposalNotReadyToAccept();

    //░▒▓█ Async/Sync Nonce Errors ██████████████████████████████████████████████▓▒░
    /// @dev Thrown when async nonce already consumed
    error AsyncNonceAlreadyUsed();

    /// @dev Thrown when sync nonce != expected sequential nonce
    error SyncNonceMismatch();

    /// @dev Thrown when reserving already-reserved async nonce
    error AsyncNonceAlreadyReserved();

    /// @dev Thrown when revoking non-reserved async nonce
    error AsyncNonceNotReserved();

    /// @dev Thrown when using reserved async nonce (general check)
    error AsyncNonceIsReserved();

    /// @dev Thrown when UserValidator blocks user transaction
    error UserCannotExecuteTransaction();

    /// @dev Thrown when using async nonce reserved by different service
    error AsyncNonceIsReservedByAnotherService();

    /// @dev Thrown when msg.sender != service address only if diferent to address(0)
    error SenderMismatch();

    /// @dev Thrown when reserving nonce with service == address(0)
    error InvalidServiceAddress();

    //░▒▓█ Token List Errors ████████████████████████████████████████████████████▓▒░
    /**
     * @dev Thrown when a token is in
     *    - the denylist (if the denylist is active)
     *    - not in the allowlist (if the allowlist is active)
     */
    error TokenIsDeniedForExecution();

    /// @dev Thrown when list status is invalid (not 0x00, 0x01, or 0x02)
    error InvalidListStatus();

    //░▒▓█ Reward Distribution State ██████████████████████████████████████████████████████▓▒░

    error RewardFlowDistributionChangeNotAllowed();

    error BaseRewardIncreaseNotAllowed();

    //░▒▓█ Total Supply State ██████████████████████████████████████████████████████▓▒░

    error MaxSupplyDeletionNotAllowed();
}
